import Foundation

struct CodexQuotaSnapshot: Equatable, Sendable, Encodable {
    struct Limits: Equatable, Sendable, Encodable {
        let fiveHour: QuotaWindow?
        let weekly: QuotaWindow?

        init?(fiveHour: QuotaWindow?, weekly: QuotaWindow?) {
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
        /// Usable credits soonest-expiring first. Nil means the backend returned no details.
        let credits: [ResetCredit]?
    }

    struct ResetCredit: Equatable, Identifiable, Sendable, Encodable {
        let id: String
        let title: String
        let expiresAt: Date?

        func canUse(at date: Date) -> Bool {
            expiresAt.map { $0 > date } ?? true
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
            let title = title.flatMap { $0.isEmpty ? nil : $0 } ?? id
            self.title = title.caseInsensitiveCompare("gpt-reserve") == .orderedSame ? "Reserve quota" : title
            self.limits = limits
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
