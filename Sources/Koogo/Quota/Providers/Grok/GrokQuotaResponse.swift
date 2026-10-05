import Foundation

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
