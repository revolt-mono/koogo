protocol QuotaSource: Sendable {
    func load() async -> QuotaReading
}

extension EnumMap where Key == QuotaProvider, Value == any QuotaSource {
    init(codex: any QuotaSource, claude: any QuotaSource, grok: any QuotaSource) {
        self.init { provider in
            switch provider {
            case .codex: codex
            case .claude: claude
            case .grok: grok
            }
        }
    }
}
