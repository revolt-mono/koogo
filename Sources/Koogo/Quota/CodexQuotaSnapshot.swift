import Foundation

struct CodexQuotaSnapshot: Equatable, Sendable, Encodable {
    struct Limits: Equatable, Sendable, Encodable {
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

    struct Account: Equatable, Sendable, Encodable {
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

    struct ResetCredits: Equatable, Sendable, Encodable {
        let availableCount: UInt64
        let nextExpiration: Date?

        init(availableCount: UInt64, availableExpirations: [Date]) {
            self.availableCount = availableCount
            nextExpiration = availableCount > 0 ? availableExpirations.min() : nil
        }
    }

    struct Model: Equatable, Identifiable, Sendable, Encodable {
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

    struct Window: Equatable, Sendable, Encodable {
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
