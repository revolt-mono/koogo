import Foundation

protocol UsageSource: Sendable {
    /// log directories relative to the tool's home.
    var logDirectories: [String] { get }
    var logFormat: UsageLogFormat { get }
    var splitsUsageByModel: Bool { get }
    /// rereads the home's model catalog; returns true when names may have changed.
    mutating func refresh(home: URL) -> Bool
    func modelName(_ model: ModelID) -> String?
}

extension UsageSource {
    var splitsUsageByModel: Bool { true }

    mutating func refresh(home: URL) -> Bool { false }
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

    func logRoots(under root: URL) -> [UsageLogRoot] {
        let source = usageSource
        return source.logDirectories.map {
            UsageLogRoot(
                provider: self,
                path: home(under: root).appending(path: $0, directoryHint: .isDirectory).path,
                format: source.logFormat
            )
        }
    }
}
