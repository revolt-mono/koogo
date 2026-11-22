import Foundation

struct UsageModelNames: Sendable {
  mutating func refresh(providers: [Provider], under root: URL) {
    if providers.contains(.piAgent) {
      piCatalog.refresh(home: Provider.piAgent.home(under: root))
    }
  }

  func name(of model: ModelID, billedBy provider: Provider) -> String {
    let name: String? =
      switch provider {
      case .codex: CodexUsagePricing.displayName(of: model)
      case .claude: ClaudeUsagePricing.displayName(of: model)
      case .piAgent: piCatalog.name(of: model)
      case .grok: nil
      }
    return name ?? model.rawValue
  }

  private var piCatalog = PiModelCatalog()
}

extension Provider {
  /// a grok turn prices all of its models as one event.
  var splitsUsageByModel: Bool {
    switch self {
    case .codex,
         .claude,
         .piAgent: true
    case .grok: false
    }
  }
}
