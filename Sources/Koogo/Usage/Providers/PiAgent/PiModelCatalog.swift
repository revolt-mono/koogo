import CryptoKit
import Foundation

/// Display names from Pi's model store and the user's custom model file.
struct PiModelCatalog: Sendable {
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

    private var names: [ModelID: String] = [:]
    private var sourceDigests: [SHA256.Digest?] = [nil, nil]

    static func modelID(provider: String, model: String) -> ModelID {
        ModelID("\(provider)/\(model)")
    }

    /// Rereads both files when their bytes changed. Returns true when any name changed.
    mutating func refresh(home: URL) -> Bool {
        let store = try? Data(contentsOf: home.appending(path: "models-store.json", directoryHint: .notDirectory))
        let custom = try? Data(contentsOf: home.appending(path: "models.json", directoryHint: .notDirectory))
        let digests = [store, custom].map { $0.map { SHA256.hash(data: $0) } }
        guard digests != sourceDigests else {
            return false
        }
        sourceDigests = digests
        var names: [ModelID: String] = [:]
        for (provider, configuration) in Self.decode([String: StoredProvider].self, from: store) ?? [:] {
            for model in configuration.models {
                names[Self.modelID(provider: provider, model: model.id)] = model.name
            }
        }
        for (provider, configuration) in Self.decode(CustomModels.self, from: custom, allowsJSON5: true)?
            .providers ?? [:]
        {
            for model in configuration.models ?? [] {
                names[Self.modelID(provider: provider, model: model.id)] = model.name ?? model.id
            }
            for (model, override) in configuration.modelOverrides ?? [:] {
                guard let name = override.name else {
                    continue
                }
                names[Self.modelID(provider: provider, model: model)] = name
            }
        }
        guard names != self.names else {
            return false
        }
        self.names = names
        return true
    }

    /// The catalog name, or the bare model id for models the catalog does not list.
    func name(of model: ModelID) -> String? {
        names[model] ?? model.rawValue.split(separator: "/", maxSplits: 1).last.map(String.init)
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
