import Foundation

/// Everything the pipeline needs from one provider's tool: where its logs are, how to read them, and what to call its models. One adapter per provider, registered by `Provider.usageSource`.
protocol UsageSource: Sendable {
    /// Directories under the tool's home that hold logs.
    var logDirectories: [String] { get }
    var logFormat: UsageLogFormat { get }
    var splitsUsageByModel: Bool { get }
    /// Rereads any model catalog under the tool's home. Returns true when a name may have changed.
    mutating func refresh(home: URL) -> Bool
    /// The display name of a logged model, or nil when the provider has none for it.
    func modelName(_ model: ModelID) -> String?
}

extension UsageSource {
    var splitsUsageByModel: Bool { true }

    mutating func refresh(home: URL) -> Bool { false }

    func logRoots(of provider: Provider, home root: URL) -> [UsageLogRoot] {
        logDirectories.map {
            UsageLogRoot(
                provider: provider,
                url: provider.home(under: root).appending(path: $0, directoryHint: .isDirectory),
                format: logFormat
            )
        }
    }
}

extension Provider {
    var usageSource: any UsageSource {
        switch self {
        case .codex: CodexUsageSource()
        case .claude: ClaudeUsageSource()
        case .piAgent: PiUsageSource()
        case .grok: GrokUsageSource()
        }
    }
}
