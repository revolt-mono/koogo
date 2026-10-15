import Foundation
import os

struct PersistedValue<Value: Codable> {
    let key: String
    let defaults: UserDefaults

    func load() -> Value? {
        decode(Value.self)
    }

    func loadDecodableElements<Element: Codable>() -> [Element]? where Value == [Element] {
        guard let elements = decode([Lossy<Element>].self) else {
            return nil
        }
        let dropped = elements.count { $0.value == nil }
        if dropped > 0 {
            Logger.app.warning("dropped \(dropped) undecodable elements of \(key, privacy: .public)")
        }
        return elements.compactMap(\.value)
    }

    func save(_ value: Value) {
        do {
            defaults.set(try PropertyListEncoder().encode(value), forKey: key)
        } catch {
            Logger.app.warning("dropped unencodable \(key, privacy: .public): \(error, privacy: .public)")
        }
    }

    private func decode<Decoded: Decodable>(_: Decoded.Type) -> Decoded? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        do {
            return try PropertyListDecoder().decode(Decoded.self, from: data)
        } catch {
            Logger.app.warning("dropped undecodable \(key, privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }
}

private struct Lossy<Element: Decodable>: Decodable {
    let value: Element?

    init(from decoder: any Decoder) {
        value = try? Element(from: decoder)
    }
}
