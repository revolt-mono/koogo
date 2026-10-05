import Foundation

/// Display names for logged model ids: the price tables name Codex, Claude, and Grok models, and Pi's catalog names Pi models. An unknown model shows its id.
struct ModelNames: Sendable {
    private var piCatalog = PiModelCatalog()

    /// Rereads the catalogs of the given providers. Returns true when any name changed.
    mutating func refresh(home: URL, providers: [Provider]) -> Bool {
        guard providers.contains(.piAgent) else {
            return false
        }
        return piCatalog.refresh(home: Provider.piAgent.home(under: home))
    }

    func name(_ provider: Provider, _ model: ModelID) -> String {
        let name =
            switch provider {
            case .codex: CodexUsagePricing.displayName(of: model)
            case .claude: ClaudeUsagePricing.displayName(of: model)
            case .grok: GrokUsagePricing.displayName(of: model)
            case .piAgent: piCatalog.name(of: model)
            }
        return name ?? model.rawValue
    }
}
