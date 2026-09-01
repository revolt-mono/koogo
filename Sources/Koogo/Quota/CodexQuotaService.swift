import Foundation

/// Why no quota is shown; surfaced in telemetry and the `--report` output.
enum CodexQuotaUnavailability: String, Error, Encodable, Sendable {
    case binaryNotFound
    case timedOut
    case sessionFailed
    case emptyLimits
}

struct CodexQuotaService: Sendable {
    private struct Timeout: Error {}

    private let executableURL: URL?

    init(executableURL: URL? = nil) {
        self.executableURL = executableURL
    }

    @concurrent
    func fetch() async -> Result<CodexQuotaSnapshot, CodexQuotaUnavailability> {
        let result: Result<CodexQuotaSnapshot, CodexQuotaUnavailability>
        if let executableURL = executableURL ?? Self.findExecutable() {
            do {
                let snapshot = try await withThrowingTaskGroup(of: CodexQuotaSnapshot?.self) { group in
                    group.addTask { try await CodexQuotaSession(executableURL: executableURL).run() }
                    group.addTask {
                        try await Task.sleep(for: .seconds(15))
                        throw Timeout()
                    }
                    defer { group.cancelAll() }
                    // Two racing children are in flight, so next() cannot return nil.
                    return try await group.next()!
                }
                result = snapshot.map(Result.success) ?? .failure(.emptyLimits)
            } catch is Timeout {
                result = .failure(.timedOut)
            } catch {
                result = .failure(.sessionFailed)
            }
        } else {
            result = .failure(.binaryNotFound)
        }

        switch result {
        case .success:
            Telemetry.quota.info("fetch available")
        case .failure(let reason):
            Telemetry.quota.info("fetch unavailable reason=\(reason.rawValue, privacy: .public)")
        }
        return result
    }

    private static func findExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates =
            [
                home.appending(path: ".codex/packages/standalone/current/bin/codex"),
                home.appending(path: ".local/bin/codex"),
                URL(filePath: "/opt/homebrew/bin/codex"),
                URL(filePath: "/usr/local/bin/codex"),
            ]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(filePath: String($0)).appending(path: "codex") }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
