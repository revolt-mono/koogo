import Foundation

struct ClaudeUsageSource: UsageSource {
    let logDirectories = ["projects"]
    let logFormat = UsageLogFormat(match: .fileExtension(".jsonl")) { ParsedLog<ClaudeUsageLogParser>($0, since: $1) }

    func modelName(_ model: ModelID) -> String? {
        ClaudeUsagePricing.displayName(of: model)
    }
}
