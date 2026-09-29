import Foundation

/// One rate-limit window as the panel shows it: what it is called, how much is left, and when it refills.
struct QuotaWindow: Equatable, Sendable, Encodable {
    let title: String
    let remainingPercent: Int
    let resetsAt: Date?

    /// Clamps `usedPercent` to 0...100 and floors it, as the providers' own usage screens do, so 3.9% used
    /// leaves 97%.
    init(title: String, usedPercent: Double, resetsAt: Date?) {
        self.title = title
        remainingPercent = 100 - Int(Double.minimum(Double.maximum(usedPercent, 0), 100).rounded(.down))
        self.resetsAt = resetsAt
    }
}

/// What one provider reports about its limits: account-wide windows, windows tied to one model, and any
/// banked resets. At least one of the three is present.
struct QuotaSnapshot: Equatable, Sendable, Encodable {
    /// Limits that apply to one model instead of the whole account; at least one window.
    struct ModelLimits: Equatable, Identifiable, Sendable, Encodable {
        let id: String
        let title: String
        let windows: [QuotaWindow]

        init?(id: String, title: String, windows: [QuotaWindow]) {
            guard !windows.isEmpty else { return nil }
            self.id = id
            self.title = title
            self.windows = windows
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

    let account: [QuotaWindow]
    let models: [ModelLimits]
    let resetCredits: ResetCredits?

    init?(account: [QuotaWindow], models: [ModelLimits] = [], resetCredits: ResetCredits? = nil) {
        guard !account.isEmpty || !models.isEmpty || resetCredits != nil else { return nil }
        self.account = account
        self.models = models
        self.resetCredits = resetCredits
    }
}
