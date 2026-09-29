extension UsageProvider {
    /// The one place that maps a provider to its log format; ingestion never names a provider type.
    var logSource: any UsageLogSource {
        switch self {
        case .codex: CodexUsageSource()
        case .claude: ClaudeUsageSource()
        case .piAgent: PiUsageSource()
        case .grok: GrokUsageSource()
        }
    }
}
