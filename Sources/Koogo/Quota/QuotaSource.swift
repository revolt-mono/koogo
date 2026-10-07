/// One provider's tool, asked for the account's limits. A source never throws: every failure is a reading.
protocol QuotaSource: Sendable {
    func load() async -> QuotaReading
}

extension QuotaUnavailability {
    init(_ failure: ToolFailure) {
        self =
            switch failure {
            case .notFound: .binaryNotFound
            case .timedOut: .timedOut
            case .cancelled, .closed, .invalidMessage, .rpc: .sessionFailed
            }
    }
}

/// One tool per quota provider. Codex is typed for the banked reset only it supports, so the reset and the regular read share one tool.
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
