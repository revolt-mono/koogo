import Foundation

struct UsageLogLocation: Sendable {
    let provider: UsageProvider
    let url: URL
}

/// Where each provider keeps its logs under one home directory.
struct UsageLocations: Sendable {
    let home: URL

    static let standard = Self(home: FileManager.default.homeDirectoryForCurrentUser)

    /// The directory a provider creates when installed, such as `~/.codex`.
    func home(of provider: UsageProvider) -> URL {
        home.appending(path: provider.logSource.homePath, directoryHint: .isDirectory)
    }

    /// Every log root, in report order.
    var logRoots: [UsageLogLocation] {
        UsageProvider.allCases.flatMap { provider in
            provider.logSource.logDirectories.map { directory in
                UsageLogLocation(
                    provider: provider,
                    url: home(of: provider).appending(path: directory, directoryHint: .isDirectory)
                )
            }
        }
    }

    /// Providers whose home exists; a few `stat` calls, cheap enough for every panel open.
    func installedProviders() -> Set<UsageProvider> {
        Set(UsageProvider.allCases.filter { FileManager.default.fileExists(atPath: home(of: $0).path) })
    }
}
