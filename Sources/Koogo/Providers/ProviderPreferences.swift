import Foundation
import Observation

/// The user's provider choices: display order, which providers show usage, and which fetch quota.
@MainActor
@Observable
final class ProviderPreferences {
    private struct Stored: Codable {
        var order: [Provider]
        var usageDisabled: Set<Provider>
        var quotaDisabled: Set<QuotaProvider>
    }

    private let storage: PersistedValue<Stored>
    /// Disabled sets are stored so a provider added later starts on.
    private var stored: Stored {
        didSet { storage.save(stored) }
    }

    var order: [Provider] { stored.order }

    /// Providers that show usage, in display order.
    var usageProviders: [Provider] {
        order.filter(isUsageEnabled)
    }

    /// Providers that fetch quota, in display order.
    var quotaProviders: [QuotaProvider] {
        order.compactMap(quotaProvider(for:))
    }

    func isUsageEnabled(_ provider: Provider) -> Bool {
        !stored.usageDisabled.contains(provider)
    }

    func isQuotaEnabled(_ provider: QuotaProvider) -> Bool {
        !stored.quotaDisabled.contains(provider)
    }

    /// The quota a provider's usage card shows. Quota renders inside that card, so a provider hidden from usage fetches none.
    func quotaProvider(for provider: Provider) -> QuotaProvider? {
        guard isUsageEnabled(provider), let quota = provider.quota, isQuotaEnabled(quota) else {
            return nil
        }
        return quota
    }

    init(defaults: UserDefaults = .standard) {
        storage = PersistedValue(key: "provider-preferences", defaults: defaults)
        let loaded = storage.load()
        let storedOrder = (loaded?.order ?? []).reduce(into: [Provider]()) { if !$0.contains($1) { $0.append($1) } }
        stored = Stored(
            order: storedOrder + Provider.allCases.filter { !storedOrder.contains($0) },
            usageDisabled: loaded?.usageDisabled ?? [],
            quotaDisabled: loaded?.quotaDisabled ?? []
        )
    }

    func move(_ provider: Provider, to destination: Provider) {
        guard let source = order.firstIndex(of: provider),
            let target = order.firstIndex(of: destination),
            source != target
        else { return }
        var order = order
        order.remove(at: source)
        order.insert(provider, at: target)
        stored.order = order
    }

    func setUsage(_ isEnabled: Bool, for provider: Provider) {
        if isEnabled {
            stored.usageDisabled.remove(provider)
        } else {
            stored.usageDisabled.insert(provider)
        }
    }

    func setQuota(_ isEnabled: Bool, for provider: QuotaProvider) {
        if isEnabled {
            stored.quotaDisabled.remove(provider)
        } else {
            stored.quotaDisabled.insert(provider)
        }
    }
}
