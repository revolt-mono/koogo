import Foundation

struct GrokUsageSource: UsageSource {
    let logDirectories = ["sessions"]
    let logFormat = UsageLogFormat(match: .fileName("updates.jsonl")) { GrokSessionLog($0, since: $1) }
    /// Grok bills every model a prompt used under its primary model.
    let splitsUsageByModel = false

    func modelName(_ model: ModelID) -> String? {
        GrokUsagePricing.displayName(of: model)
    }
}
