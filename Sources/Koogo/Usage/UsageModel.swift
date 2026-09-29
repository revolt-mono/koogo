import Foundation
import Observation

@MainActor
@Observable
final class UsageModel {
    private static let disabledProvidersKey = "usage-disabled-providers"
    private static let providerOrderKey = "usage-provider-order"

    private let usageService: UsageService
    private let defaults: UserDefaults
    private let now: @MainActor () -> Date
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var needsRefresh = false

    private(set) var snapshot: UsageSnapshot?
    /// Persisted as the disabled set, so providers added later start enabled.
    private(set) var enabledProviders: Set<Provider>
    /// The order providers show in the panel and settings; providers added later go last.
    private(set) var providerOrder: [Provider]

    init(
        usageService: UsageService,
        defaults: UserDefaults = .standard,
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        self.usageService = usageService
        self.defaults = defaults
        self.now = now
        let disabled = (defaults.stringArray(forKey: Self.disabledProvidersKey) ?? [])
            .compactMap(Provider.init(rawValue:))
        enabledProviders = Set(Provider.allCases).subtracting(disabled)
        let stored = (defaults.stringArray(forKey: Self.providerOrderKey) ?? [])
            .compactMap(Provider.init(rawValue:))
        // First occurrence wins, so every provider lands exactly once even if the stored list repeats one.
        providerOrder = (stored + Provider.allCases).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    /// Moves `provider` into `destination`'s slot; the rows between shift toward the vacated one.
    func moveProvider(_ provider: Provider, to destination: Provider) {
        guard let source = providerOrder.firstIndex(of: provider),
            let target = providerOrder.firstIndex(of: destination),
            source != target
        else { return }
        providerOrder.remove(at: source)
        providerOrder.insert(provider, at: target)
        defaults.set(providerOrder.map(\.rawValue), forKey: Self.providerOrderKey)
    }

    func setEnabled(_ isEnabled: Bool, for provider: Provider) {
        if isEnabled {
            enabledProviders.insert(provider)
        } else {
            enabledProviders.remove(provider)
        }
        let disabled = Provider.allCases.filter { !enabledProviders.contains($0) }
        defaults.set(disabled.map(\.rawValue), forKey: Self.disabledProvidersKey)
        refresh()
    }

    /// Starts a refresh, or queues exactly one trailing rerun while one is in flight, and returns the
    /// enabled providers installed right now; only these have logs read.
    @discardableResult
    func refresh() -> Set<Provider> {
        let active = enabledProviders.intersection(usageService.locations.installedProviders())
        guard !isRefreshing else {
            needsRefresh = true
            return active
        }
        let date = now()
        isRefreshing = true
        Task(priority: .utility) {
            snapshot = await usageService.refresh(at: date, providers: active).snapshot
            isRefreshing = false
            if needsRefresh {
                needsRefresh = false
                refresh()
            }
        }
        return active
    }
}
