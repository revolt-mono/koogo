import Darwin
import Foundation
import os

struct PiModelCatalog: Sendable {
  static func modelID(provider: String, model: String) -> ModelID {
    ModelID(rawValue: "\(provider)/\(model)")
  }

  mutating func refresh(home: URL) {
    let storeURL = home.appending(path: "models-store.json", directoryHint: .notDirectory)
    let customURL = home.appending(path: "models.json", directoryHint: .notDirectory)
    let versions = [storeURL, customURL].map(SourceVersion.init)
    guard versions != sourceVersions else {
      return
    }
    sourceVersions = versions
    names = Self.names(storeURL: storeURL, customURL: customURL)
  }

  func name(of model: ModelID) -> String? {
    names[model] ?? model.rawValue.split(separator: "/", maxSplits: 1).last.map(String.init)
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

  /// file change time advances on writes, renames, and attribute changes, and cannot be set back.
  private struct SourceVersion: Equatable {
    init?(_ url: URL) {
      var status = Darwin.stat()
      guard stat(url.path, &status) == 0 else {
        return nil
      }
      identity = UsageFileMetadata.Identity(status)
      changeSeconds = status.st_ctimespec.tv_sec
      changeNanoseconds = status.st_ctimespec.tv_nsec
    }

    let identity: UsageFileMetadata.Identity
    let changeSeconds: Int
    let changeNanoseconds: Int
  }

  private var names = [ModelID: String]()
  private var sourceVersions: [SourceVersion?] = [nil, nil]

  private static func names(storeURL: URL, customURL: URL) -> [ModelID: String] {
    var names = [ModelID: String]()
    let stored = decode([String: StoredProvider].self, at: storeURL) ?? [:]
    for (provider, configuration) in stored {
      for model in configuration.models {
        names[modelID(provider: provider, model: model.id)] = model.name
      }
    }
    let custom = decode(CustomModels.self, at: customURL, allowsJSON5: true)?.providers ?? [:]
    for (provider, configuration) in custom {
      for model in configuration.models ?? [] {
        names[modelID(provider: provider, model: model.id)] = model.name ?? model.id
      }
      for (model, override) in configuration.modelOverrides ?? [:] {
        guard let name = override.name else {
          continue
        }
        names[modelID(provider: provider, model: model)] = name
      }
    }
    return names
  }

  private static func decode<Value: Decodable>(
    _ type: Value.Type,
    at url: URL,
    allowsJSON5: Bool = false,
  ) -> Value? {
    guard let data = try? Data(contentsOf: url) else {
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
