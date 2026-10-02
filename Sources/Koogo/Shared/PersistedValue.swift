import Foundation

/// One property-list value under one `UserDefaults` key.
struct PersistedValue<Value: Codable> {
    let key: String
    let defaults: UserDefaults

    func load() -> Value? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        do {
            return try PropertyListDecoder().decode(Value.self, from: data)
        } catch {
            Telemetry.app.warning("dropped undecodable \(key, privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }

    func save(_ value: Value) {
        guard let data = try? PropertyListEncoder().encode(value) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}
