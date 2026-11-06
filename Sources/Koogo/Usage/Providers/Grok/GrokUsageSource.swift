import Foundation

struct GrokUsageSource: UsageSource {
    let logDirectories = ["sessions"]
    /// grok parent usage includes subagents; skipping subagent logs avoids double counting.
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
    /// a grok turn prices all of its models as one event.
    let splitsUsageByModel = false
}

private struct GrokSessionSummary: Decodable {
    let kind: String?

    private enum CodingKeys: String, CodingKey {
        case kind = "session_kind"
    }
}
