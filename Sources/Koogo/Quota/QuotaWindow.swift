import Foundation

/// One rate-limit window as the panel shows it: how much is left and when it refills.
struct QuotaWindow: Equatable, Sendable, Encodable {
    let remainingPercent: Int
    let resetsAt: Date?

    /// Clamps `usedPercent` to 0...100 and floors it, as the providers' own usage screens do, so 3.9% used
    /// leaves 97%.
    init(usedPercent: Double, resetsAt: Date?) {
        remainingPercent = 100 - Int(Double.minimum(Double.maximum(usedPercent, 0), 100).rounded(.down))
        self.resetsAt = resetsAt
    }
}

/// One scope's session and weekly windows; at least one is present.
struct QuotaLimits: Equatable, Sendable, Encodable {
    let session: QuotaWindow?
    let weekly: QuotaWindow?

    init?(session: QuotaWindow?, weekly: QuotaWindow?) {
        guard session != nil || weekly != nil else {
            return nil
        }
        self.session = session
        self.weekly = weekly
    }
}

/// Limits that apply to one model instead of the whole account.
struct ModelQuotaLimits: Equatable, Identifiable, Sendable, Encodable {
    let id: String
    let title: String
    let limits: QuotaLimits
}
