import Foundation

/// One rate-limit window as the panel shows it: how much is left and when it refills.
struct QuotaWindow: Equatable, Sendable, Encodable {
    let remainingPercent: Int
    let resetsAt: Date?

    init(usedPercent: Int, resetsAt: Date?) {
        remainingPercent = 100 - min(max(usedPercent, 0), 100)
        self.resetsAt = resetsAt
    }
}
