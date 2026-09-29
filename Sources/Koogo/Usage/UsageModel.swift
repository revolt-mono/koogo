import Foundation
import Observation

@MainActor
@Observable
final class UsageModel {
    private static let disabledProvidersKey = "usage-disabled-providers"

    private let usageService: UsageService
    private let defaults: UserDefaults
    private let now: @MainActor () -> Date
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var needsRefresh = false

    private(set) var snapshot: UsageSnapshot?
    /// Persisted as the disabled set, so providers added later start enabled.
    private(set) var enabledProviders: Set<Provider>

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
