import Foundation

extension Provider {
    var usageLogDirectories: [String] {
        switch self {
        case .codex: ["sessions", "archived_sessions"]
        case .claude: ["projects"]
        case .piAgent: ["sessions"]
        case .grok: ["sessions"]
        }
    }

    /// Grok bills every model a prompt used under its primary model.
    var splitsUsageByModel: Bool {
        switch self {
        case .codex, .claude, .piAgent: true
        case .grok: false
        }
    }

    func usageLogRoots(home root: URL) -> [UsageLogRoot] {
        let match: UsageLogRoot.Match =
            switch self {
            case .codex, .claude, .piAgent: .fileExtension(".jsonl")
            case .grok: .fileName("updates.jsonl")
            }
        let open: @Sendable (URL, Date) -> (any TrackedLog)? =
            switch self {
            case .codex: { ParsedLog<CodexUsageLogParser>($0, since: $1) }
            case .claude: { ParsedLog<ClaudeUsageLogParser>($0, since: $1) }
            case .piAgent: { ParsedLog<PiUsageLogParser>($0, since: $1) }
            case .grok: { GrokSessionLog($0, since: $1) }
            }
        return usageLogDirectories.map {
            UsageLogRoot(
                provider: self,
                url: home(under: root).appending(path: $0, directoryHint: .isDirectory),
                match: match,
                open: open
            )
        }
    }
}
