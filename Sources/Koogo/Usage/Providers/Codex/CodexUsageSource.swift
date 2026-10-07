import Foundation

struct CodexUsageSource: UsageSource {
    let logDirectories = ["sessions", "archived_sessions"]
    let logFormat = UsageLogFormat.jsonLines(CodexUsageLogParser.self)

    func modelName(_ model: ModelID) -> String? {
        CodexUsagePricing.displayName(of: model)
    }
}
