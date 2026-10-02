import Foundation

extension Provider {
    /// The tool's configuration directory under the given user home.
    func home(under root: URL) -> URL {
        root.appending(path: homePath, directoryHint: .isDirectory)
    }

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
        let match: LogMatch =
            switch self {
            case .codex, .claude, .piAgent: .fileExtension(".jsonl")
            case .grok: .fileName("updates.jsonl")
            }
        return usageLogDirectories.map {
            UsageLogRoot(
                provider: self,
                url: home(under: root).appending(path: $0, directoryHint: .isDirectory),
                match: match
            )
        }
    }

    /// Admits a discovered file as a log, or returns nil when the file is not one or cannot be read.
    func openUsageLog(at url: URL, since windowStart: Date) -> (any TrackedLog)? {
        switch self {
        case .codex: ParsedLog<CodexLogParser>(url, since: windowStart)
        case .claude: ParsedLog<ClaudeLogParser>(url, since: windowStart)
        case .piAgent: ParsedLog<PiLogParser>(url, since: windowStart)
        case .grok: GrokSessionLog(url, since: windowStart)
        }
    }
}
