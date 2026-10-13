import Foundation
import Observation

@MainActor
@Observable
final class ProviderPreferences {
    private struct Stored: Codable {
        var order: [Provider]
        var usageDisabled: Set<Provider>
    }

    private let storage: PersistedValue<Stored>
    /// The disabled set is stored so a provider added later starts on.
    private var stored: Stored {
        didSet { storage.save(stored) }
    }

    var order: [Provider] { stored.order }

    var usageProviders: [Provider] {
        order.filter { self[usage: $0] }
    }

    /// Quota renders inside the usage card, so a provider hidden from usage fetches none.
    var quotaProviders: [QuotaProvider] {
        usageProviders.compactMap(\.quota)
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

    init(defaults: UserDefaults = .standard) {
        storage = PersistedValue(key: "provider-preferences", defaults: defaults)
        let loaded = storage.load()
        var seen = Set<Provider>()
        let storedOrder = (loaded?.order ?? []).filter { seen.insert($0).inserted }
        stored = Stored(
            order: storedOrder + Provider.allCases.filter { !storedOrder.contains($0) },
            usageDisabled: loaded?.usageDisabled ?? []
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
