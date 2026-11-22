import Foundation

extension UsageLogFormat {
  /// grok parent usage includes subagents; skipping subagent logs avoids double counting.
  static let grokSessionUpdates = Self(
    GrokUsageLogParser.self,
    match: .fileName("updates.jsonl"),
    admits: GrokSessionSummary.isParentSession(loggingTo:),
  )
}

private struct GrokSessionSummary: Decodable {
  let kind: String?

  static func isParentSession(loggingTo path: String) throws -> Bool {
    let summaryURL = URL(filePath: path).deletingLastPathComponent().appending(path: "summary.json")
    let summary = try JSONDecoder().decode(Self.self, from: Data(contentsOf: summaryURL))
    return summary.kind?.hasPrefix("subagent") != true
  }

  private enum CodingKeys: String, CodingKey {
    case kind = "session_kind"
  }
}
