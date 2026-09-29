import CryptoKit
import Foundation

struct PiModelCatalog: Sendable {
    private struct ID: Hashable, Sendable {
        let provider: String
        let model: String
    }

    private struct StoredModel: Decodable {
        let id: String
        let name: String
    }

    private struct CustomModel: Decodable {
        let id: String
        let name: String?
    }

    private struct ModelOverride: Decodable {
        let name: String?
    }

    private struct StoredProvider: Decodable {
        let models: [StoredModel]
    }

    private struct CustomProvider: Decodable {
        let models: [CustomModel]?
        let modelOverrides: [String: ModelOverride]?
    }

    private struct CustomModels: Decodable {
        let providers: [String: CustomProvider]
    }

    static let empty = PiModelCatalog()

    private var names: [ID: String] = [:]
    private var sourceDigests: [SHA256.Digest?] = [nil, nil]

    /// Reloads the names Pi keeps under its `home`: `models-store.json`, then the JSON5 `models.json`
    /// entries and overrides on top. Returns whether either file changed.
    mutating func refresh(home: URL) -> Bool {
        let store = try? Data(contentsOf: home.appending(path: "models-store.json", directoryHint: .notDirectory))
        let custom = try? Data(contentsOf: home.appending(path: "models.json", directoryHint: .notDirectory))
        // Compares content, including same-size rewrites, without retaining configuration secrets.
        let digests = [store, custom].map { $0.map { SHA256.hash(data: $0) } }
        guard digests != sourceDigests else {
            return false
        }
        sourceDigests = digests
        names = [:]
        for (provider, configuration) in Self.decode([String: StoredProvider].self, from: store) ?? [:] {
            for model in configuration.models {
                names[ID(provider: provider, model: model.id)] = model.name
            }
        }
        for (provider, configuration) in Self.decode(CustomModels.self, from: custom, allowsJSON5: true)?
            .providers ?? [:]
        {
            for model in configuration.models ?? [] {
                names[ID(provider: provider, model: model.id)] = model.name ?? model.id
            }
            for (model, override) in configuration.modelOverrides ?? [:] {
                guard let name = override.name else {
                    continue
                }
                names[ID(provider: provider, model: model)] = name
            }
        }
        return true
    }

    func displayName(provider: String, model: String) -> String {
        names[ID(provider: provider, model: model)] ?? model
    }

    private static func decode<Value: Decodable>(
        _ type: Value.Type,
        from data: Data?,
        allowsJSON5: Bool = false
    ) -> Value? {
        guard let data else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = allowsJSON5
        return try? decoder.decode(type, from: data)
    }
}
