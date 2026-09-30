import Foundation

struct UsageLogLocation: Sendable {
    let provider: Provider
    let url: URL
}

struct UsageLocations: Sendable {
    let home: URL

    static let standard = Self(home: FileManager.default.homeDirectoryForCurrentUser)

    func home(of provider: Provider) -> URL {
        home.appending(path: provider.logSource.homePath, directoryHint: .isDirectory)
    }

    var logRoots: [UsageLogLocation] {
        Provider.allCases.flatMap { provider in
            provider.logSource.logDirectories.map { directory in
                UsageLogLocation(
                    provider: provider,
                    url: home(of: provider).appending(path: directory, directoryHint: .isDirectory)
                )
            }
        }
    }

    func installedProviders() -> Set<Provider> {
        Set(Provider.allCases.filter { FileManager.default.fileExists(atPath: home(of: $0).path) })
    }
}
