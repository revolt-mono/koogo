import Foundation

struct CodexUsageSource: UsageSource {
    let logDirectories = ["sessions", "archived_sessions"]
    let logFormat = UsageLogFormat(match: .fileExtension(".jsonl")) { ParsedLog<CodexUsageLogParser>($0, since: $1) }

    func modelName(_ model: ModelID) -> String? {
        CodexUsagePricing.displayName(of: model)
    }
}
