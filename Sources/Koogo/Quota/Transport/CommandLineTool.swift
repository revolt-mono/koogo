import Darwin
import Foundation
import Synchronization

struct CommandLineTool: Sendable {
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

    static func candidates(named name: String, preferring preferred: [URL] = []) -> [URL] {
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map {
            URL(filePath: String($0))
        }
        return (preferred + installDirectories + path).map { $0.appending(path: name) }
    }

    /// Runs one conversation over the tool's standard streams. A decoding error inside the session is an invalid message; any other error means the tool closed the conversation.
    func session<Value: Sendable>(
        _ arguments: [String],
        in directory: URL? = nil,
        _ session: @escaping @Sendable (_ input: FileHandle, _ output: LineReader) throws -> Value
    ) async throws(ToolFailure) -> Value {
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
        else { throw .notFound }
        let input = Pipe()
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw .closed
        }
        do {
            return try await ProcessGroupLifetime.run(timeout: timeout) { processGroup in
                let process = Process()
                let output = Pipe()
                process.executableURL = executable
                process.arguments = arguments
                process.currentDirectoryURL = directory
                process.standardInput = input
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                // A fixed environment keeps the launching shell's switches, such as a Claude Code session's CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC, out of the tool. HOME and USER locate its credentials.
                let searchPath = ([executable.deletingLastPathComponent()] + Self.installDirectories).map(\.path)
                process.environment = [
                    "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                    "USER": NSUserName(),
                    "PATH": (searchPath + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]).joined(separator: ":"),
                ]

                defer {
                    processGroup.terminate()
                    try? input.fileHandleForWriting.close()
                    if process.isRunning {
                        process.waitUntilExit()
                    }
                    try? output.fileHandleForReading.close()
                    processGroup.finish()
                }
                try processGroup.start(process)
                return try session(input.fileHandleForWriting, LineReader(fileHandle: output.fileHandleForReading))
            }
        } catch let failure as ToolFailure {
            throw failure
        } catch is CancellationError {
            throw .cancelled
        } catch is DecodingError {
            throw .invalidMessage
        } catch {
            throw .closed
        }
    }
}
