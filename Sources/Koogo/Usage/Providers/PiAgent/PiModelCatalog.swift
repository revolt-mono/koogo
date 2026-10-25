import Darwin
import Foundation
import os

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

    /// file change time advances on writes, renames, and attribute changes, and cannot be set back.
    private struct SourceVersion: Equatable {
        let identity: UsageFileMetadata.Identity
        let changeSeconds: Int
        let changeNanoseconds: Int

        init?(_ url: URL) {
            var status = Darwin.stat()
            guard stat(url.path, &status) == 0 else {
                return nil
            }
            identity = UsageFileMetadata.Identity(status)
            changeSeconds = status.st_ctimespec.tv_sec
            changeNanoseconds = status.st_ctimespec.tv_nsec
        }
    }

    private var names: [ModelID: String] = [:]
    private var sourceVersions: [SourceVersion?] = [nil, nil]

    static func modelID(provider: String, model: String) -> ModelID {
        ModelID("\(provider)/\(model)")
    }

    /// returns true when model names change.
    mutating func refresh(home: URL) -> Bool {
        let storeURL = home.appending(path: "models-store.json", directoryHint: .notDirectory)
        let customURL = home.appending(path: "models.json", directoryHint: .notDirectory)
        let versions = [storeURL, customURL].map(SourceVersion.init)
        guard versions != sourceVersions else {
            return false
        }
        sourceVersions = versions
        let store = try? Data(contentsOf: storeURL)
        let custom = try? Data(contentsOf: customURL)
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
        do {
            return try decoder.decode(type, from: data)
        } catch {
            Logger.usage.warning("dropped undecodable pi \(type, privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }
}
