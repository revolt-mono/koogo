import Foundation

struct CodexQuotaSnapshot: Equatable, Sendable {
    struct Limits: Equatable, Sendable {
        let fiveHour: Window?
        let weekly: Window?

        init?(fiveHour: Window?, weekly: Window?) {
            guard fiveHour != nil || weekly != nil else {
                return nil
            }
            self.fiveHour = fiveHour
            self.weekly = weekly
        }
    }

    struct Account: Equatable, Sendable {
        let limits: Limits?
        let resetCredits: ResetCredits?

        init?(limits: Limits?, resetCredits: ResetCredits?) {
            guard limits != nil || resetCredits != nil else {
                return nil
            }
            self.limits = limits
            self.resetCredits = resetCredits
        }
    }

    struct ResetCredits: Equatable, Sendable {
        let availableCount: UInt64
        let nextExpiration: Date?

        init(availableCount: UInt64, availableExpirations: [Date]) {
            self.availableCount = availableCount
            nextExpiration = availableCount > 0 ? availableExpirations.min() : nil
        }
    }

    struct Model: Equatable, Identifiable, Sendable {
        let id: String
        let title: String
        let limits: Limits

        init?(id: String, title: String?, limits: Limits) {
            guard !id.isEmpty else {
                return nil
            }
            self.id = id
            if let title, !title.isEmpty {
                self.title = title
            } else {
                self.title = id
            }
            self.limits = limits
        }
    }

    struct Window: Equatable, Sendable {
        let remainingPercent: Int
        let resetsAt: Date?

        init(usedPercent: Int, resetsAt: Date?) {
            remainingPercent = 100 - min(max(usedPercent, 0), 100)
            self.resetsAt = resetsAt
        }
    }

    let account: Account?
    let models: [Model]

    init?(account: Account?, models: [Model]) {
        guard account != nil || !models.isEmpty else {
            return nil
        }
        self.account = account
        self.models = models
    }
}

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
