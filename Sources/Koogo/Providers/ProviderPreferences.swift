import Foundation
import Observation

/// app-scoped; has nothing to start.
@MainActor
@Observable
final class ProviderPreferences {
  init(defaults: UserDefaults) {
    storage = PersistedValue(key: "provider-preferences", defaults: defaults)
    let loaded = storage.load()
    var seen = Set<Provider>()
    stored = Stored(
      order: ((loaded?.order ?? []) + Provider.allCases).filter { seen.insert($0).inserted },
      usageDisabled: loaded?.usageDisabled ?? [],
    )
  }

  var order: [Provider] {
    stored.order
  }

  var usageProviders: [Provider] {
    order.filter { self[isUsageEnabled: $0] }
  }

  var quotaProviders: [QuotaProvider] {
    usageProviders.compactMap(\.quota)
  }

  subscript(isUsageEnabled provider: Provider) -> Bool {
    get { !stored.usageDisabled.contains(provider) }
    set {
      if newValue {
        stored.usageDisabled.remove(provider)
      } else {
        stored.usageDisabled.insert(provider)
      }
    }
  }

  func move(_ provider: Provider, to destination: Provider) {
    guard
      let source = order.firstIndex(of: provider),
      let target = order.firstIndex(of: destination),
      source != target
    else { return }
    var order = order
    order.remove(at: source)
    order.insert(provider, at: target)
    stored.order = order
  }

  private struct Stored: Codable {
    var order: [Provider]
    var usageDisabled: Set<Provider>
  }

  private let storage: PersistedValue<Stored>

  private var stored: Stored {
    didSet { storage.save(stored) }
  }
}
