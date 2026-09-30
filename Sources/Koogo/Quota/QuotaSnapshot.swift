import Foundation

struct QuotaWindow: Equatable, Sendable, Encodable {
    let title: String
    let usedPercent: Int
    let resetsAt: Date?

    init(title: String, usedPercent: Double, resetsAt: Date?) {
        self.title = title
        self.usedPercent = Int(Double.minimum(Double.maximum(usedPercent, 0), 100).rounded(.down))
        self.resetsAt = resetsAt
    }
}

struct QuotaSnapshot: Equatable, Sendable, Encodable {
    struct ResetCredits: Equatable, Sendable, Encodable {
        let availableCount: UInt64
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
