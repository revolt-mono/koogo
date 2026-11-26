protocol QuotaSource: Sendable {
  func load() async -> QuotaReading
}

extension QuotaReading {
  init(_ failure: ToolFailure) {
    self =
      switch failure {
      case .upstreamDenied(let reason): .paused(reason)
      case .notFound: .unavailable(.binaryNotFound)
      case .timedOut: .unavailable(.timedOut)
      case .closed,
           .rpc: .unavailable(.sessionFailed)
      case .invalidMessage: .unavailable(.invalidMessage)
      }
  }
}

struct QuotaSources: Sendable {
  static var production: Self {
    QuotaSources(codex: CodexQuotaSource(), claude: ClaudeQuotaSource(), grok: GrokQuotaSource())
  }

  let codex: any CodexQuotaResetSource
  let claude: any QuotaSource
  let grok: any QuotaSource

  subscript(provider: QuotaProvider) -> any QuotaSource {
    switch provider {
    case .codex: codex
    case .claude: claude
    case .grok: grok
    }
  }

  func loadAll() async -> EnumMap<QuotaProvider, QuotaReading> {
    async let codex = codex.load()
    async let claude = claude.load()
    async let grok = grok.load()
    let readings = await (codex: codex, claude: claude, grok: grok)
    return EnumMap { provider in
      switch provider {
      case .codex: readings.codex
      case .claude: readings.claude
      case .grok: readings.grok
      }
    }
  }
}
