import Foundation

/// One rate-limit window as the panel shows it: what it is called, how much is used, and when it refills.
struct QuotaWindow: Equatable, Sendable, Encodable {
    let title: String
    let usedPercent: Int
    let resetsAt: Date?

    /// Clamps `usedPercent` to 0...100 and floors it, as the providers' own usage screens do, so 3.9% used
    /// shows 3%.
    init(title: String, usedPercent: Double, resetsAt: Date?) {
        self.title = title
        self.usedPercent = Int(Double.minimum(Double.maximum(usedPercent, 0), 100).rounded(.down))
        self.resetsAt = resetsAt
    }
}

/// What one provider reports about its limits: its windows, the fixed-period ones first and then any the
/// provider names, and any banked resets. At least one of the two is present.
struct QuotaSnapshot: Equatable, Sendable, Encodable {
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

    let windows: [QuotaWindow]
    let resetCredits: ResetCredits?

    init?(windows: [QuotaWindow], resetCredits: ResetCredits? = nil) {
        guard !windows.isEmpty || resetCredits != nil else { return nil }
        self.windows = windows
        self.resetCredits = resetCredits
    }
}
