import Foundation

/// The Grok Build credit limit: one weekly or monthly window per account.
struct GrokQuotaSnapshot: Equatable, Sendable, Encodable {
    enum Period: String, Sendable, Encodable {
        case weekly
        case monthly
    }

    /// Nil when the backend reports a period this app does not know.
    let period: Period?
    let window: QuotaWindow
}
