enum QuotaUnavailability: String, Error, Encodable, Sendable {
    case binaryNotFound
    case timedOut
    case sessionFailed
    case emptyLimits

    init(_ error: any Error) {
        self =
            switch error {
            case CommandLineTool.Failure.notFound: .binaryNotFound
            case CommandLineTool.Failure.timedOut: .timedOut
            default: .sessionFailed
            }
    }
}

protocol QuotaSource: Sendable {
    func load() async -> Result<QuotaSnapshot, QuotaUnavailability>
}

extension Provider {
    static let quotaSources: [Provider: any QuotaSource] = [
        .codex: CodexQuotaSource(),
        .claude: ClaudeQuotaSource(),
        .grok: GrokQuotaSource(),
    ]
}
