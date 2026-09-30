import Foundation

/// The result of Grok's `x.ai/billing` extension, using the credits-config fields.
struct GrokQuotaResponse: Decodable {
    struct Config: Decodable {
        /// Proto3 omits zero-valued scalars, so an untouched allowance has no percentage field.
        let creditUsagePercent: Double?
        let currentPeriod: Period?
    }

    struct Period: Decodable {
        let type: String?
        let end: Date?
    }

    let config: Config?

    /// The Grok Build credit limit: one weekly or monthly window per account, or a window of unknown
    /// period that keeps the allowance and reset date.
    var snapshot: QuotaSnapshot? {
        guard let config else { return nil }
        let title =
            switch config.currentPeriod?.type {
            case "USAGE_PERIOD_TYPE_WEEKLY": "Weekly"
            case "USAGE_PERIOD_TYPE_MONTHLY": "Monthly limit"
            default: "Usage limit"
            }
        return QuotaSnapshot(windows: [
            QuotaWindow(title: title, usedPercent: config.creditUsagePercent ?? 0, resetsAt: config.currentPeriod?.end)
        ])
    }
}
