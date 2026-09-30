import Darwin
import Foundation
import Synchronization

/// A local command-line tool, launched from the first executable candidate in its own process group with a
/// fixed environment whose `PATH` starts with its directory and the known install directories, so launcher
/// scripts find their runtime. A timeout or cancellation stops the whole group, including descendants that
/// keep a pipe open after the tool exits.
struct CommandLineTool: Sendable {
    enum Failure: Error {
        /// No candidate is an executable file.
        case notFound
        case timedOut
        /// The tool exited unsuccessfully or wrote more output than is read.
        case failed
    }

    fileprivate static let outputLimit = 4 * 1_024 * 1_024
    /// Where tools and their runtimes install outside the system `PATH`: `~/.local/bin`, Homebrew, and
    /// `/usr/local/bin`.
    private static let installDirectories = [
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin"),
        URL(filePath: "/opt/homebrew/bin"),
        URL(filePath: "/usr/local/bin"),
    ]

    private let candidates: [URL]
    private let timeout: Duration

    init(candidates: [URL], timeout: Duration) {
        self.candidates = candidates
        self.timeout = timeout
    }

    /// `name` in each of `preferred`, then in the install directories, then in every `PATH` entry.
    static func candidates(named name: String, preferring preferred: [URL] = []) -> [URL] {
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map {
            URL(filePath: String($0))
        }
        return (preferred + installDirectories + path).map { $0.appending(path: name) }
    }

    /// Runs the tool to completion in `directory` with standard input closed and returns its standard output.
    func output(of arguments: [String], in directory: URL) async throws -> Data {
        try await run(arguments, in: directory, input: nil) { process, output in
            var data = Data()
            while let chunk = try output.read(upToCount: 64 * 1_024), !chunk.isEmpty {
                data.append(chunk)
                guard data.count <= Self.outputLimit else { throw Failure.failed }
            }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw Failure.failed }
            return data
        }
    }

    /// Starts the tool and runs `session` against its standard input and output; the tool stops when `session`
    /// returns. Lines longer than the output limit fail the session.
    func session<Value: Sendable>(
        _ arguments: [String],
        in directory: URL? = nil,
        _ session: @escaping @Sendable (_ input: FileHandle, _ output: LineReader) throws -> Value
    ) async throws -> Value {
        let input = Pipe()
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw Failure.failed
        }
        return try await run(arguments, in: directory, input: input) { _, output in
            try session(input.fileHandleForWriting, LineReader(fileHandle: output))
        }
    }

    private func run<Value: Sendable>(
        _ arguments: [String],
        in directory: URL?,
        input: Pipe?,
        _ body: @escaping @Sendable (Process, FileHandle) throws -> Value
    ) async throws -> Value {
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
        else { throw Failure.notFound }
        return try await ProcessGroupLifetime.run(timeout: timeout) { processGroup in
            let process = Process()
            let output = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = directory
            process.standardInput = input.map { $0 as Any } ?? FileHandle.nullDevice
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            // A fixed environment keeps the launching shell's switches, such as a Claude Code session's
            // CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC, out of the tool. HOME and USER locate its credentials.
            let searchPath = ([executable.deletingLastPathComponent()] + Self.installDirectories).map(\.path)
            process.environment = [
                "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                "USER": NSUserName(),
                "PATH": (searchPath + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]).joined(separator: ":"),
            ]

            // Terminating first also stops a server that ignores its input closing.
            defer {
                processGroup.terminate()
                try? input?.fileHandleForWriting.close()
                if process.isRunning {
                    process.waitUntilExit()
                }
                try? output.fileHandleForReading.close()
                processGroup.finish()
            }
            try processGroup.start(process)
            return try body(process, output.fileHandleForReading)
        }
    }
}

/// Splits a tool's output into lines, holding at most the output limit of an unfinished line.
struct LineReader {
    private let fileHandle: FileHandle
    private var buffer = Data()

    fileprivate init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
    }

    /// The next line without its newline; a final unterminated line is returned at end of output.
    mutating func nextLine() throws -> Data? {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                return line
            }
            let chunk = fileHandle.availableData
            if chunk.isEmpty {
                guard !buffer.isEmpty else {
                    return nil
                }
                defer { buffer.removeAll() }
                return buffer
            }
            buffer.append(chunk)
            guard buffer.count <= CommandLineTool.outputLimit else {
                throw CommandLineTool.Failure.failed
            }
        }
    }
}

/// Owns a tool's process group across launch, cancellation, and cleanup.
private final class ProcessGroupLifetime: Sendable {
    private enum State {
        case pending
        case running(Process)
        case terminating(Process)
        case stopped
    }

    private let state = Mutex(State.pending)

    /// Runs blocking pipe I/O off the cooperative executor. Cancellation and `timeout` terminate
    /// the group so reads unblock through EOF.
    static func run<Value: Sendable>(
        timeout: Duration,
        _ operation: @escaping @Sendable (ProcessGroupLifetime) throws -> Value
    ) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask {
                let processGroup = ProcessGroupLifetime()
                return try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { continuation in
                        DispatchQueue.global(qos: .utility).async {
                            continuation.resume(with: Result { try operation(processGroup) })
                        }
                    }
                } onCancel: {
                    processGroup.terminate()
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw CommandLineTool.Failure.timedOut
            }
            defer { group.cancelAll() }
            // Two racing children are in flight, so next() cannot return nil.
            return try await group.next()!
        }
    }

    func start(_ process: Process) throws {
        try state.withLock { state in
            switch state {
            case .pending:
                try process.run()
                guard getpgid(process.processIdentifier) == process.processIdentifier else {
                    Darwin.kill(process.processIdentifier, SIGKILL)
                    process.waitUntilExit()
                    throw CocoaError(.executableLoad)
                }
                state = .running(process)
            case .stopped:
                throw CancellationError()
            case .running, .terminating:
                preconditionFailure("process group lifetime cannot start twice")
            }
        }
    }

    func finish() {
        state.withLock { state in
            if case .terminating(let process) = state,
                Self.processGroupExists(process.processIdentifier)
            {
                return
            }
            state = .stopped
        }
    }

    func terminate() {
        let process = state.withLock { state -> Process? in
            switch state {
            case .pending:
                state = .stopped
                return nil
            case .running(let process) where Self.processGroupExists(process.processIdentifier):
                state = .terminating(process)
                return process
            case .running:
                state = .stopped
                return nil
            case .terminating, .stopped:
                return nil
            }
        }
        guard let process else {
            return
        }
        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGTERM)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            self.forceTerminate()
        }
    }

    private func forceTerminate() {
        guard
            let process = state.withLock({ state -> Process? in
                guard case .terminating(let process) = state else {
                    return nil
                }
                state = .stopped
                return process
            })
        else {
            return
        }
        Darwin.kill(-process.processIdentifier, SIGKILL)
    }

    private static func processGroupExists(_ processGroupIdentifier: Int32) -> Bool {
        Darwin.kill(-processGroupIdentifier, 0) != -1 || errno != ESRCH
    }
}
