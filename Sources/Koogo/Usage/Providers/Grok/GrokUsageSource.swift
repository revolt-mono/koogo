import Foundation

struct GrokUsageSource: UsageSource {
    let logDirectories = ["sessions"]
    /// grok parent usage includes subagents; admit readable session summaries and skip subagent logs to avoid double counting.
    let logFormat = UsageLogFormat(match: .fileName("updates.jsonl")) { path, metadata, windowStart in
        let summaryURL = URL(filePath: path).deletingLastPathComponent().appending(path: "summary.json")
        guard let data = try? Data(contentsOf: summaryURL),
            let summary = try? JSONDecoder().decode(GrokSessionSummary.self, from: data),
            summary.kind?.hasPrefix("subagent") != true
        else {
            return nil
        }
        return ParsedLog<GrokUsageLogParser>(AppendOnlyFile(path, observed: metadata), since: windowStart)
    }
    /// grok bills every model used in a prompt under the primary model.
    let splitsUsageByModel = false

    func modelName(_ model: ModelID) -> String? {
        GrokUsagePricing.displayName(of: model)
    }
}

private struct GrokSessionSummary: Decodable {
    let kind: String?

    private enum CodingKeys: String, CodingKey {
        case kind = "session_kind"
    }
}
