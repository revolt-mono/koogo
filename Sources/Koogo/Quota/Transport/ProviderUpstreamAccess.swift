import Foundation

struct ProviderUpstreamAccess: Sendable {
  init(lookup: @escaping @Sendable () async throws -> (Data, URLResponse)) {
    self.lookup = lookup
  }

  enum Denial: String, Error, Encodable {
    case restrictedRegion
    case unknownRegion

    var message: String {
      switch self {
      case .restrictedRegion: "Provider access paused in this region."
      case .unknownRegion: "Provider access paused. Region unknown."
      }
    }
  }

  static let live = ProviderUpstreamAccess {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForResource = 2
    // A new session cannot reuse an open connection from the previous route.
    let session = URLSession(configuration: configuration)
    defer { session.finishTasksAndInvalidate() }
    return try await session.data(from: URL(string: "https://api.country.is/")!)
  }

  func denial() async -> Denial? {
    guard
      let (data, response) = try? await lookup(),
      (response as? HTTPURLResponse)?.statusCode == 200,
      let country = try? JSONDecoder().decode(CountryResponse.self, from: data).country,
      NSLocale.isoCountryCodes.contains(country)
    else { return .unknownRegion }
    return country == "CN" ? .restrictedRegion : nil
  }

  private struct CountryResponse: Decodable {
    let country: String
  }

  private let lookup: @Sendable () async throws -> (Data, URLResponse)
}
