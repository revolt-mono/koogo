import Foundation
import Observation

@MainActor
@Observable
final class QuotaModel {
    private static let disabledProvidersKey = "quota-disabled-providers"
    private static let cooldown: Duration = .seconds(60)

    private let sources: [Provider: any QuotaSource]
    private let defaults: UserDefaults
    @ObservationIgnored private var refreshAfter: [Provider: ContinuousClock.Instant] = [:]
    private var busy: Set<Provider> = []

    private(set) var states: [Provider: QuotaState]

    var providers: [Provider] { Provider.allCases.filter { sources[$0] != nil } }

    init(sources: [Provider: any QuotaSource] = Provider.quotaSources, defaults: UserDefaults = .standard) {
        self.sources = sources
        self.defaults = defaults
        let disabled = (defaults.stringArray(forKey: Self.disabledProvidersKey) ?? [])
            .compactMap(Provider.init(rawValue:))
        states = sources.keys.filter { !disabled.contains($0) }.reduce(into: [:]) { $0[$1] = .loading }
    }

    func isEnabled(_ provider: Provider) -> Bool {
        states[provider] != nil
    }

    func isBusy(_ provider: Provider) -> Bool {
        busy.contains(provider)
    }

    func setEnabled(_ isEnabled: Bool, for provider: Provider) {
        guard sources[provider] != nil else { return }
        states[provider] = isEnabled ? states[provider] ?? .loading : nil
        defaults.set(providers.filter { states[$0] == nil }.map(\.rawValue), forKey: Self.disabledProvidersKey)
    }

    func refresh(_ provider: Provider, force: Bool = false) {
        let inCooldown = refreshAfter[provider].map { ContinuousClock.now < $0 } ?? false
        guard let source = sources[provider], states[provider] != nil, !busy.contains(provider), force || !inCooldown
        else { return }
        busy.insert(provider)
        Task { await read(provider, from: source) }
    }

    func write<Value: Sendable>(
        to provider: Provider,
        _ operation: @escaping @Sendable () async -> Value
    ) -> Task<Value, Never>? {
        guard let source = sources[provider], !busy.contains(provider) else { return nil }
        busy.insert(provider)
        return Task {
            let value = await operation()
            await read(provider, from: source)
            return value
        }
    }

    private func read(_ provider: Provider, from source: any QuotaSource) async {
        let state: QuotaState
        switch await source.load() {
        case .success(let snapshot):
            Telemetry.quota.info("\(provider.rawValue, privacy: .public) fetch available")
            refreshAfter[provider] = .now + Self.cooldown
            state = .available(snapshot)
        case .failure(let reason):
            Telemetry.quota.info(
                "\(provider.rawValue, privacy: .public) fetch unavailable reason=\(reason.rawValue, privacy: .public)"
            )
            refreshAfter[provider] = nil
            state = .unavailable(reason)
        }
        if states[provider] != nil {
            states[provider] = state
        }
        busy.remove(provider)
    }
}
