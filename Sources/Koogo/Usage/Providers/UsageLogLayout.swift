import Foundation

extension Provider {
    /// Directories under the provider's home that hold usage logs.
    var usageLogDirectories: [String] {
        switch self {
        case .codex: ["sessions", "archived_sessions"]
        case .claude: ["projects"]
        case .piAgent: ["sessions"]
        case .grok: ["sessions"]
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
            case .codex: { ParsedLog<CodexLogParser>($0, since: $1) }
            case .claude: { ParsedLog<ClaudeLogParser>($0, since: $1) }
            case .piAgent: { ParsedLog<PiLogParser>($0, since: $1) }
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
