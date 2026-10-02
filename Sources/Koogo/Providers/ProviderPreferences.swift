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

    private(set) var order: [Provider]
    private(set) var usageEnabled: Set<Provider>
    private(set) var quotaEnabled: Set<QuotaProvider>

    /// Providers that show usage, in display order.
    var usageProviders: [Provider] {
        order.filter(usageEnabled.contains)
    }

    /// Providers that fetch quota, in display order. Quota renders inside a provider's usage card, so a
    /// provider hidden from usage fetches none.
    var quotaProviders: [QuotaProvider] {
        usageProviders.compactMap(\.quota).filter(quotaEnabled.contains)
    }

    init(defaults: UserDefaults = .standard) {
        storage = PersistedValue(key: "provider-preferences", defaults: defaults)
        let stored = storage.load()
        let storedOrder = (stored?.order ?? []).reduce(into: [Provider]()) { if !$0.contains($1) { $0.append($1) } }
        order = storedOrder + Provider.allCases.filter { !storedOrder.contains($0) }
        usageEnabled = Set(Provider.allCases).subtracting(stored?.usageDisabled ?? [])
        quotaEnabled = Set(QuotaProvider.allCases).subtracting(stored?.quotaDisabled ?? [])
    }

    func move(_ provider: Provider, to destination: Provider) {
        guard let source = order.firstIndex(of: provider),
            let target = order.firstIndex(of: destination),
            source != target
        else { return }
        order.remove(at: source)
        order.insert(provider, at: target)
        save()
    }

    func setUsage(_ isEnabled: Bool, for provider: Provider) {
        if isEnabled {
            usageEnabled.insert(provider)
        } else {
            usageEnabled.remove(provider)
        }
        save()
    }

    func setQuota(_ isEnabled: Bool, for provider: QuotaProvider) {
        if isEnabled {
            quotaEnabled.insert(provider)
        } else {
            quotaEnabled.remove(provider)
        }
        save()
    }

    private func save() {
        storage.save(
            Stored(
                order: order,
                usageDisabled: Set(Provider.allCases).subtracting(usageEnabled),
                quotaDisabled: Set(QuotaProvider.allCases).subtracting(quotaEnabled)
            )
        )
    }
}
