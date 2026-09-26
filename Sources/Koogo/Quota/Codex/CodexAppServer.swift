import Darwin
import Foundation
import Synchronization

/// Talks to `codex app-server --stdio`: each call launches the server in its own process group,
/// completes the handshake, sends one JSON-RPC request and tears the group down. JSON-RPC error
/// codes are interpreted only here.
struct CodexAppServer: Sendable {
    enum Failure: Error, Equatable, Sendable {
        case binaryNotFound
        case timedOut
        case sessionFailed
        /// JSON-RPC -32601: this Codex version does not know the method.
        case methodNotFound
        case rpc(code: Int)
    }

    struct CallError: Error {
        let failure: Failure
        /// The method request started writing, so the server may have acted on it.
        let requestMayHaveArrived: Bool
    }

    private let executableCandidates: [URL]
    private let timeout: Duration

    /// The first executable candidate at call time is launched.
    init(executableCandidates: [URL], timeout: Duration) {
        self.executableCandidates = executableCandidates
        self.timeout = timeout
    }

    /// Codex's own install locations, then every `PATH` entry.
    static func standardCandidates() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let installs = [
            home.appending(path: ".codex/packages/standalone/current/bin/codex"),
            home.appending(path: ".local/bin/codex"),
            URL(filePath: "/opt/homebrew/bin/codex"),
            URL(filePath: "/usr/local/bin/codex"),
        ]
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
        return installs + path.map { URL(filePath: String($0)).appending(path: "codex") }
    }

    /// Sends `method` without a params key.
    func call<Value: Decodable & Sendable>(_ method: String) async throws(CallError) -> Value {
        try await call(RPCMessage<Never>(method: method, id: 2))
    }

    func call<Value: Decodable & Sendable, Params: Encodable & Sendable>(
        _ method: String,
        params: Params
    ) async throws(CallError) -> Value {
        try await call(RPCMessage(method: method, id: 2, params: params))
    }

    private func call<Value: Decodable & Sendable, Params: Encodable & Sendable>(
        _ request: RPCMessage<Params>
    ) async throws(CallError) -> Value {
        let executable = executableCandidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
        guard let executable else {
            throw CallError(failure: .binaryNotFound, requestMayHaveArrived: false)
        }
        // Flipped right before the request is written, so a later failure may still have reached the server.
        let requestStarted = Mutex(false)
        do {
            return try await withThrowingTaskGroup(of: Value.self) { group in
                group.addTask {
                    try await Self.session(executable: executable) { connection in
                        requestStarted.withLock { $0 = true }
                        return try connection.request(request)
                    }
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw Failure.timedOut
                }
                defer { group.cancelAll() }
                // Two racing children are in flight, so next() cannot return nil.
                return try await group.next()!
            }
        } catch {
            let failure: Failure =
                switch error {
                case let failure as Failure: failure
                case let error as RPCError where error.code == -32601: .methodNotFound
                case let error as RPCError: .rpc(code: error.code)
                default: .sessionFailed
                }
            throw CallError(failure: failure, requestMayHaveArrived: requestStarted.withLock { $0 })
        }
    }

    /// Pipe I/O and `waitUntilExit` block, so the session runs on GCD rather than a cooperative
    /// thread. Cancellation terminates the process group, which unblocks reads through EOF.
    private static func session<Value: Sendable>(
        executable: URL,
        operation: @escaping @Sendable (inout RPCConnection) throws -> Value
    ) async throws -> Value {
        let processGroup = ProcessGroupLifetime()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(
                        with: Result {
                            try blockingSession(
                                executable: executable,
                                processGroup: processGroup,
                                operation: operation
                            )
                        }
                    )
                }
            }
        } onCancel: {
            processGroup.terminate()
        }
    }

    private static func blockingSession<Value>(
        executable: URL,
        processGroup: ProcessGroupLifetime,
        operation: (inout RPCConnection) throws -> Value
    ) throws -> Value {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw Failure.sessionFailed
        }
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = [executable.deletingLastPathComponent().path, environment["PATH"]]
            .compactMap { $0 }
            .joined(separator: ":")
        process.environment = environment

        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning {
                process.waitUntilExit()
            }
            try? output.fileHandleForReading.close()
            processGroup.finish()
        }
        try processGroup.start(process)

        // Also terminate on protocol errors; closing stdin alone need not stop app-server.
        defer { processGroup.terminate() }
        var connection = RPCConnection(
            input: input.fileHandleForWriting,
            reader: LineReader(fileHandle: output.fileHandleForReading)
        )
        let _: InitializeResponse = try connection.request(
            RPCMessage(
                method: "initialize",
                id: 1,
                params: ["clientInfo": ["name": "koogo", "title": "Koogo", "version": "1.0"]]
            )
        )
        try connection.send(RPCMessage<Never>(method: "initialized"))
        return try operation(&connection)
    }
}

private struct RPCConnection {
    let input: FileHandle
    var reader: LineReader

    func send<Params: Encodable & Sendable>(_ message: RPCMessage<Params>) throws {
        var data = try JSONEncoder().encode(message)
        data.append(0x0A)
        try input.write(contentsOf: data)
    }

    mutating func request<Value: Decodable, Params: Encodable & Sendable>(
        _ message: RPCMessage<Params>
    ) throws -> Value {
        try send(message)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        while let data = try reader.nextLine() {
            guard let envelope = try? decoder.decode(RPCEnvelope.self, from: data), envelope.id == message.id
            else {
                continue
            }
            return try decoder.decode(RPCSuccess<Value>.self, from: data).result
        }
        throw CodexAppServer.Failure.sessionFailed
    }
}

private final class ProcessGroupLifetime: Sendable {
    private enum State {
        case pending
        case running(Process)
        case terminating(Process)
        case stopped
    }

    private let state = Mutex(State.pending)

    func start(_ process: Process) throws {
        try state.withLock { state in
            switch state {
            case .pending:
                try process.run()
                guard getpgid(process.processIdentifier) == process.processIdentifier else {
                    Darwin.kill(process.processIdentifier, SIGKILL)
                    process.waitUntilExit()
                    throw CodexAppServer.Failure.sessionFailed
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

private struct LineReader {
    let fileHandle: FileHandle
    var buffer = Data()

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
            guard buffer.count <= 4 * 1_024 * 1_024 else {
                throw CodexAppServer.Failure.sessionFailed
            }
        }
    }
}

/// Nil `id` marks a notification; nil `params` is omitted from the wire.
private struct RPCMessage<Params: Encodable & Sendable>: Encodable, Sendable {
    let method: String
    var id: Int?
    var params: Params?
}

private struct RPCEnvelope: Decodable {
    let id: Int?
}

private struct RPCError: Decodable, Error {
    let code: Int
}

private struct RPCSuccess<Result: Decodable>: Decodable {
    let result: Result

    private enum CodingKeys: CodingKey {
        case result
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.error) {
            throw try container.decode(RPCError.self, forKey: .error)
        }
        result = try container.decode(Result.self, forKey: .result)
    }
}

private struct InitializeResponse: Decodable {}
