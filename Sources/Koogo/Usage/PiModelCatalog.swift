import Foundation

struct PiModelCatalog: Sendable {
    private struct ID: Hashable, Sendable {
        let provider: String
        let model: String
    }

    private struct Model: Decodable {
        let id: String?
        let name: String?
    }

    private struct ModelOverride: Decodable {
        let name: String?
    }

    private struct ProviderModels: Decodable {
        let models: [Model]?
        let modelOverrides: [String: ModelOverride]?
    }

    private struct CustomModels: Decodable {
        let providers: [String: ProviderModels]
    }

    static let empty = PiModelCatalog(names: [:])

    private let names: [ID: String]

    init(locations: UsageLocations.PiModels) {
        let custom = Self.decode(
            CustomModels.self,
            from: locations.custom,
            allowsJSON5: true
        )
        var names: [ID: String] = [:]
        for providers in [
            Self.decode([String: ProviderModels].self, from: locations.store) ?? [:],
            custom?.providers ?? [:],
        ] {
            for (provider, configuration) in providers {
                for model in configuration.models ?? [] {
                    guard let id = nonempty(model.id), let name = nonempty(model.name) else {
                        continue
                    }
                    names[ID(provider: provider, model: id)] = name
                }
            }
        }
        for (provider, configuration) in custom?.providers ?? [:] {
            for (model, override) in configuration.modelOverrides ?? [:] {
                guard let model = nonempty(model), let name = nonempty(override.name) else {
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
