extension Provider {
    var logSource: any UsageLogSource {
        switch self {
        case .codex: CodexUsageSource()
        case .claude: ClaudeUsageSource()
        case .piAgent: PiUsageSource()
        case .grok: GrokUsageSource()
        }
    }
}
