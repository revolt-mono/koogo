protocol QuotaSource: Sendable {
    func load() async -> QuotaReading
}

extension QuotaUnavailability {
    init(_ failure: ToolFailure) {
        self =
            switch failure {
            case .notFound: .binaryNotFound
            case .timedOut: .timedOut
            case .closed, .rpc: .sessionFailed
            case .invalidMessage: .invalidMessage
            }
    }
}

struct QuotaSources: Sendable {
    let codex: any CodexQuotaResetSource
    let claude: any QuotaSource
    let grok: any QuotaSource

    static var production: Self {
        QuotaSources(codex: CodexQuotaSource(), claude: ClaudeQuotaSource(), grok: GrokQuotaSource())
    }

    subscript(provider: QuotaProvider) -> any QuotaSource {
        switch provider {
        case .codex: codex
        case .claude: claude
        case .grok: grok
        }
    }
}
