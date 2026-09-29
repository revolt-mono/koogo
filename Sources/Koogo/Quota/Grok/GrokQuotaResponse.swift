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

    var snapshot: GrokQuotaSnapshot? {
        guard let config else { return nil }
        let period: GrokQuotaSnapshot.Period? =
            switch config.currentPeriod?.type {
            case "USAGE_PERIOD_TYPE_WEEKLY": .weekly
            case "USAGE_PERIOD_TYPE_MONTHLY": .monthly
            default: nil
            }
        return GrokQuotaSnapshot(
            period: period,
            window: QuotaWindow(usedPercent: config.creditUsagePercent ?? 0, resetsAt: config.currentPeriod?.end)
        )
    }
}
