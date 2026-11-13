protocol QuotaSource: Sendable {
  func load() async -> QuotaReading
}

extension QuotaUnavailability {
  init(_ failure: ToolFailure) {
    self =
      switch failure {
      case .notFound: .binaryNotFound
      case .timedOut: .timedOut
      case .closed,
           .rpc: .sessionFailed
      case .invalidMessage: .invalidMessage
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
}
