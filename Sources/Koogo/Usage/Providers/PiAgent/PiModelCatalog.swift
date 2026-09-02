import Foundation

struct PiModelCatalog: Equatable, Sendable {
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

    static let empty = PiModelCatalog(names: [:])

    private let names: [ID: String]

    init(locations: UsageLocations.PiModels) {
        var names: [ID: String] = [:]
        for (provider, configuration) in Self.decode([String: StoredProvider].self, from: locations.store) ?? [:] {
            for model in configuration.models {
                names[ID(provider: provider, model: model.id)] = model.name
            }
        }
        for (provider, configuration) in Self.decode(CustomModels.self, from: locations.custom, allowsJSON5: true)?
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
        self.names = names
    }

    private init(names: [ID: String]) {
        self.names = names
    }

    func displayName(provider: String, model: String) -> String {
        names[ID(provider: provider, model: model)] ?? model
    }

    private static func decode<Value: Decodable>(
        _ type: Value.Type,
        from url: URL,
        allowsJSON5: Bool = false
    ) -> Value? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = allowsJSON5
        return try? decoder.decode(type, from: data)
    }
}
