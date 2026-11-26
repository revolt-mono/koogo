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

  static let lookupTimeout: TimeInterval = 2

  static let live = ProviderUpstreamAccess {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    configuration.timeoutIntervalForResource = lookupTimeout
    // A new session cannot reuse an open connection from the previous route.
    let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }
    return try await session.data(from: URL(string: "https://api.country.is/")!)
  }

  func verify() async throws {
    let result = try? await lookup()
    try Task.checkCancellation()
    guard
      let (data, response) = result,
      (response as? HTTPURLResponse)?.statusCode == 200,
      let country = try? JSONDecoder().decode(CountryResponse.self, from: data).country,
      NSLocale.isoCountryCodes.contains(country)
    else { throw Denial.unknownRegion }
    if country == "CN" {
      throw Denial.restrictedRegion
    }
  }

  private struct CountryResponse: Decodable {
    let country: String
  }

  private let lookup: @Sendable () async throws -> (Data, URLResponse)
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _: URLSession,
    task _: URLSessionTask,
    willPerformHTTPRedirection _: HTTPURLResponse,
    newRequest _: URLRequest,
  ) async -> URLRequest? {
    nil
  }
}
