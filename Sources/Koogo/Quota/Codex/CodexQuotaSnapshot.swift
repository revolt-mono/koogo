import Foundation

struct CodexQuotaSnapshot: Equatable, Sendable, Encodable {
    struct Account: Equatable, Sendable, Encodable {
        let limits: QuotaLimits?
        let resetCredits: ResetCredits?

        init?(limits: QuotaLimits?, resetCredits: ResetCredits?) {
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

    let account: Account?
    let models: [ModelQuotaLimits]

    init?(account: Account?, models: [ModelQuotaLimits]) {
        guard account != nil || !models.isEmpty else {
            return nil
        }
        self.account = account
        self.models = models
    }
}
