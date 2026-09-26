import Foundation
import Observation

@MainActor
@Observable
final class UsageModel {
    private static let disabledProvidersKey = "usage-disabled-providers"

    private let usageService: UsageService
    private let defaults: UserDefaults
    private let now: @MainActor () -> Date
    private var isRefreshing = false

    private(set) var snapshot: UsageSnapshot?
    /// Persisted as the disabled set, so providers added later start enabled.
    private(set) var enabledProviders: Set<UsageProvider>
    /// Enabled providers that were installed at the last refresh; only these have logs read and quota fetched.
    private(set) var activeProviders: Set<UsageProvider> = []

    init(
        usageService: UsageService,
        defaults: UserDefaults = .standard,
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        self.usageService = usageService
        self.defaults = defaults
        self.now = now
        let disabled = (defaults.stringArray(forKey: Self.disabledProvidersKey) ?? [])
            .compactMap(UsageProvider.init(rawValue:))
        enabledProviders = Set(UsageProvider.allCases).subtracting(disabled)
    }

    func setEnabled(_ isEnabled: Bool, for provider: UsageProvider) {
        if isEnabled {
            enabledProviders.insert(provider)
        } else {
            enabledProviders.remove(provider)
        }
        let disabled = UsageProvider.allCases.filter { !enabledProviders.contains($0) }
        defaults.set(disabled.map(\.rawValue), forKey: Self.disabledProvidersKey)
        refresh()
    }

    func refresh() {
        activeProviders = enabledProviders.intersection(usageService.locations.logs.installedProviders())
        guard !isRefreshing else {
            return
        }
        let date = now()
        let providers = activeProviders
        isRefreshing = true
        Task(priority: .utility) {
            snapshot = await usageService.refresh(at: date, providers: providers).snapshot
            isRefreshing = false
            // A toggle or install during this refresh was coalesced away, so catch up with it.
            if providers != activeProviders {
                refresh()
            }
        }
    }
}
