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
        let path =
            switch provider {
            case .codex: ".codex"
            case .claude: ".claude"
            case .piAgent: ".pi/agent"
            case .grok: ".grok"
            }
        return home.appending(path: path, directoryHint: .isDirectory)
    }

    /// Every log root, in report order.
    var logRoots: [UsageLogLocation] {
        [
            (UsageProvider.codex, "sessions"),
            (.codex, "archived_sessions"),
            (.claude, "projects"),
            (.piAgent, "sessions"),
            (.grok, "sessions"),
        ].map { provider, directory in
            UsageLogLocation(
                provider: provider,
                url: home(of: provider).appending(path: directory, directoryHint: .isDirectory)
            )
        }
    }

    /// Providers whose home exists; a few `stat` calls, cheap enough for every panel open.
    func installedProviders() -> Set<UsageProvider> {
        Set(UsageProvider.allCases.filter { FileManager.default.fileExists(atPath: home(of: $0).path) })
    }
}
