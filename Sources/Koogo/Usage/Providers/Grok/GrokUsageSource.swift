import Foundation

struct GrokUsageSource: UsageSource {
    let logDirectories = ["sessions"]
    /// Admits a session's `updates.jsonl` once its summary is readable. A subagent session is skipped, since the parent turn that spawned it already includes its usage.
    let logFormat = UsageLogFormat(match: .fileName("updates.jsonl")) { path, metadata, windowStart in
        let summaryURL = URL(filePath: path).deletingLastPathComponent().appending(path: "summary.json")
        guard let data = try? Data(contentsOf: summaryURL),
            let summary = try? JSONDecoder().decode(GrokSessionSummary.self, from: data),
            summary.kind?.hasPrefix("subagent") != true
        else {
            return nil
        }
        return ParsedLog<GrokUsageLogParser>(path, observed: metadata, since: windowStart)
    }
    /// Grok bills every model a prompt used under its primary model.
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
