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

    var usageProviders: [Provider] {
        order.filter { self[usage: $0] }
    }

    var quotaProviders: [QuotaProvider] {
        order.compactMap(quotaProvider(for:))
    }

    subscript(usage provider: Provider) -> Bool {
        get { !stored.usageDisabled.contains(provider) }
        set {
            if newValue {
                stored.usageDisabled.remove(provider)
            } else {
                stored.usageDisabled.insert(provider)
            }
        }
    }

    subscript(quota provider: QuotaProvider) -> Bool {
        get { !stored.quotaDisabled.contains(provider) }
        set {
            if newValue {
                stored.quotaDisabled.remove(provider)
            } else {
                stored.quotaDisabled.insert(provider)
            }
        }
    }

    /// The quota a provider's usage card shows. Quota renders inside that card, so a provider hidden from usage fetches none.
    func quotaProvider(for provider: Provider) -> QuotaProvider? {
        guard self[usage: provider], let quota = provider.quota, self[quota: quota] else {
            return nil
        }
        return quota
    }

    init(defaults: UserDefaults = .standard) {
        storage = PersistedValue(key: "provider-preferences", defaults: defaults)
        let loaded = storage.load()
        var seen = Set<Provider>()
        let storedOrder = (loaded?.order ?? []).filter { seen.insert($0).inserted }
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
}
