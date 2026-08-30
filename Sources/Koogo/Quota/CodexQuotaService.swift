import Foundation

struct CodexQuotaService: Sendable {
    private struct Failure: Error {}

    private let executableURL: URL?

    init(executableURL: URL? = nil) {
        self.executableURL = executableURL
    }

    @concurrent
    func fetch() async -> CodexQuotaSnapshot? {
        guard let executableURL = executableURL ?? Self.findExecutable() else {
            return nil
        }

        do {
            return try await withThrowingTaskGroup(of: CodexQuotaSnapshot?.self) { group in
                group.addTask { try await CodexQuotaSession(executableURL: executableURL).run() }
                group.addTask {
                    try await Task.sleep(for: .seconds(15))
                    throw Failure()
                }
                guard let result = try await group.next() else {
                    throw Failure()
                }
                group.cancelAll()
                return result
            }
        } catch {
            return nil
        }
    }

    private static func findExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates = [
            home.appending(path: ".codex/packages/standalone/current/bin/codex"),
            home.appending(path: ".local/bin/codex"),
            URL(filePath: "/opt/homebrew/bin/codex"),
            URL(filePath: "/usr/local/bin/codex"),
        ]
        candidates.append(
            contentsOf: (ProcessInfo.processInfo.environment["PATH"] ?? "")
                .split(separator: ":")
                .map { URL(filePath: String($0)).appending(path: "codex") }
        )
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
