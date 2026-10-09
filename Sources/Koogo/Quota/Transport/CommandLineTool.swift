import Foundation
import Subprocess
import System

struct CommandLineTool: Sendable {
    private static let installDirectories = [
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin"),
        URL(filePath: "/opt/homebrew/bin"),
        URL(filePath: "/usr/local/bin"),
    ]
    /// A write to a tool that closed its input must fail the session instead of ending the app.
    private static let brokenPipesIgnored: Void = { signal(SIGPIPE, SIG_IGN) }()
    private static let platformOptions: PlatformOptions = {
        var options = PlatformOptions()
        // The tool leads its own session so the teardown reaches every descendant and nothing else.
        options.createSession = true
        options.teardownSequence = [.gracefulShutDown(toProcessGroup: true, allowedDurationToNextStep: .seconds(1))]
        return options
    }()

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
        _ session: @escaping @Sendable (inout ToolStreams) async throws -> Value
    ) async throws(ToolFailure) -> Value {
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
        else { throw .notFound }
        Self.brokenPipesIgnored
        do {
            return try await converse(with: executable, arguments, in: directory, session)
        } catch let failure as ToolFailure {
            throw failure
        } catch is DecodingError {
            throw .invalidMessage
        } catch let error as SubprocessError where error.code == .outputLimitExceeded {
            throw .invalidMessage
        } catch {
            throw Task.isCancelled ? .cancelled : .closed
        }
    }

    private func converse<Value: Sendable>(
        with executable: URL,
        _ arguments: [String],
        in directory: URL?,
        _ session: @escaping @Sendable (inout ToolStreams) async throws -> Value
    ) async throws -> Value {
        // A fixed environment keeps the launching shell's switches, such as a Claude Code session's CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC, out of the tool. HOME and USER locate its credentials.
        let searchPath = ([executable.deletingLastPathComponent()] + Self.installDirectories).map(\.path)
        return try await run(
            .path(FilePath(executable.path)),
            arguments: Arguments(arguments),
            environment: .custom([
                "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                "USER": NSUserName(),
                "PATH": (searchPath + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]).joined(separator: ":"),
            ]),
            workingDirectory: directory.map { FilePath($0.path) },
            platformOptions: Self.platformOptions,
            input: .inputWriter,
            output: .sequence,
            error: .discarded
        ) { execution in
            try await withThrowingTaskGroup(of: Value.self) { group in
                group.addTask {
                    var streams = ToolStreams(input: execution.standardInputWriter, output: execution.standardOutput)
                    return try await session(&streams)
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw ToolFailure.timedOut
                }
                let outcome = await Result { try await group.next()! }
                // The timeout covers the conversation, not the exit: the tool may outlive its answer, run returns only once the tool exits, and a read blocked on the tool ends only when the tool does.
                group.cancelAll()
                await execution.teardown(using: Self.platformOptions.teardownSequence)
                try? execution.send(signal: .kill, toProcessGroup: true)
                return try outcome.get()
            }
        }.closureResult
    }
}
