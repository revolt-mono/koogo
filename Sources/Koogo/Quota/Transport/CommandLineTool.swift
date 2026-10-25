import Foundation
import Subprocess
import System
import os

struct CommandLineTool: Sendable {
    private static let installDirectories = [
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin"),
        URL(filePath: "/opt/homebrew/bin"),
        URL(filePath: "/usr/local/bin"),
    ]
    /// makes writes to a closed tool input fail the session instead of terminating the app.
    private static let brokenPipesIgnored: Void = { signal(SIGPIPE, SIG_IGN) }()
    private static let platformOptions: PlatformOptions = {
        var options = PlatformOptions()
        // a separate session lets teardown reach every descendant without signaling unrelated processes.
        options.createSession = true
        options.teardownSequence = [.gracefulShutDown(toProcessGroup: true, allowedDurationToNextStep: .seconds(1))]
        return options
    }()

    /// a project-free working directory limits the tool to user-level configuration.
    private static let workingDirectory = FilePath("/tmp")

    /// the usage page waits for every quota read, so this also bounds a cold start.
    static let defaultTimeout: Duration = .seconds(10)

    private let candidates: [URL]
    private let timeout: Duration

    init(candidates: [URL], timeout: Duration = defaultTimeout) {
        self.candidates = candidates
        self.timeout = timeout
    }

    static func candidates(named name: String, preferring preferred: [URL] = []) -> [URL] {
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map {
            URL(filePath: String($0))
        }
        return (preferred + installDirectories + path).map { $0.appending(path: name) }
    }

    func session<Value: Sendable>(
        _ arguments: [String],
        _ session: @escaping @Sendable (consuming ToolStreams) async throws -> Value
    ) async throws(ToolFailure) -> Value {
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
        else { throw .notFound }
        Self.brokenPipesIgnored
        do {
            return try await converse(with: executable, arguments, session)
        } catch let failure as ToolFailure {
            throw failure
        } catch is DecodingError {
            throw .invalidMessage
        } catch let error as SubprocessError where error.code == .outputLimitExceeded {
            throw .invalidMessage
        } catch {
            Logger.quota.warning(
                "\(executable.lastPathComponent, privacy: .public) session closed: \(error, privacy: .public)"
            )
            throw .closed
        }
    }

    private func converse<Value: Sendable>(
        with executable: URL,
        _ arguments: [String],
        _ session: @escaping @Sendable (consuming ToolStreams) async throws -> Value
    ) async throws -> Value {
        // isolate the tool from launching-shell switches while preserving credential locations.
        let searchPath = ([executable.deletingLastPathComponent()] + Self.installDirectories).map(\.path)
        return try await run(
            .path(FilePath(executable.path)),
            arguments: Arguments(arguments),
            environment: .custom([
                "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                "USER": NSUserName(),
                "PATH": (searchPath + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]).joined(separator: ":"),
            ]),
            workingDirectory: Self.workingDirectory,
            platformOptions: Self.platformOptions,
            input: .inputWriter,
            output: .sequence,
            error: .discarded
        ) { execution in
            try await withThrowingTaskGroup(of: Value.self) { group in
                group.addTask {
                    try await session(
                        ToolStreams(input: execution.standardInputWriter, output: execution.standardOutput)
                    )
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw ToolFailure.timedOut
                }
                let outcome = await Result { try await group.next()! }
                // subprocess waits for tool exit; teardown also releases reads blocked beyond the conversation timeout.
                group.cancelAll()
                await execution.teardown(using: Self.platformOptions.teardownSequence)
                try? execution.send(signal: .kill, toProcessGroup: true)
                return try outcome.get()
            }
        }.closureResult
    }
}
