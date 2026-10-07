import Foundation

struct ClaudeUsageSource: UsageSource {
    let logDirectories = ["projects"]
    let logFormat = UsageLogFormat.jsonLines(ClaudeUsageLogParser.self)

    func modelName(_ model: ModelID) -> String? {
        ClaudeUsagePricing.displayName(of: model)
    }
}
