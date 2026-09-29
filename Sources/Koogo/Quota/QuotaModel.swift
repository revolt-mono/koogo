import Foundation
import Observation

/// Every provider's quota: which are switched on, what each shows, and one in-flight read or write per
/// provider. Reads coalesce and hold a cooldown; a write blocks reads and is followed by an authoritative
/// read, so a pre-write read can never overwrite the post-write snapshot.
@MainActor
@Observable
final class QuotaModel {
    private static let disabledProvidersKey = "quota-disabled-providers"
    private static let cooldown: Duration = .seconds(60)

    private let sources: [Provider: any QuotaSource]
    private let defaults: UserDefaults
    @ObservationIgnored private var refreshAfter: [Provider: ContinuousClock.Instant] = [:]
    private var busy: Set<Provider> = []

    /// One entry per switched-on provider with a quota source; the entry is the single sign a provider
    /// shows a quota at all.
    private(set) var states: [Provider: QuotaState]

    /// Providers that can show a quota.
    var providers: [Provider] { Provider.allCases.filter { sources[$0] != nil } }

    init(sources: [Provider: any QuotaSource] = Provider.quotaSources, defaults: UserDefaults = .standard) {
        self.sources = sources
        self.defaults = defaults
        // Persisted as the disabled set, so providers added later start enabled.
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

    /// Reads a switched-on provider once, keeping its current state while the read runs. Skipped while the
    /// provider is busy, and inside the cooldown unless forced.
    func refresh(_ provider: Provider, force: Bool = false) {
        let inCooldown = refreshAfter[provider].map { ContinuousClock.now < $0 } ?? false
        guard let source = sources[provider], states[provider] != nil, !busy.contains(provider), force || !inCooldown
        else { return }
        busy.insert(provider)
        Task { await read(provider, from: source) }
    }

    /// Runs `operation` as a write to `provider`, then re-reads its quota; the returned task finishes only
    /// once the state is authoritative again. Nil while the provider is busy, so nothing is sent.
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
        let result = await source.load()
        switch result {
        case .success:
            Telemetry.quota.info("\(provider.rawValue, privacy: .public) fetch available")
        case .failure(let reason):
            Telemetry.quota.info(
                "\(provider.rawValue, privacy: .public) fetch unavailable reason=\(reason.rawValue, privacy: .public)"
            )
        }
        // A provider switched off during the read stays off; one switched back on takes the result.
        states[provider]?.apply(result)
        refreshAfter[provider] = .now + Self.cooldown
        busy.remove(provider)
    }
}
