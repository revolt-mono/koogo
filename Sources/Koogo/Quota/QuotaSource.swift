/// Why a quota read shows nothing; surfaced in telemetry and the `--report` output.
enum QuotaUnavailability: String, Error, Encodable, Sendable {
    case binaryNotFound
    case timedOut
    case sessionFailed
    case emptyLimits

    /// Tool launch failures keep their kind; any other error is a failed session.
    init(_ error: any Error) {
        self =
            switch error {
            case CommandLineTool.Failure.notFound: .binaryNotFound
            case CommandLineTool.Failure.timedOut: .timedOut
            default: .sessionFailed
            }
    }
}

/// Reads one provider's quota through its local CLI, without credentials or HTTP requests of its own.
protocol QuotaSource: Sendable {
    func load() async -> Result<QuotaSnapshot, QuotaUnavailability>
}

extension Provider {
    /// The one place that maps a provider to its quota source; providers absent here show no quota.
    static let quotaSources: [Provider: any QuotaSource] = [
        .codex: CodexQuotaSource(),
        .claude: ClaudeQuotaSource(),
        .grok: GrokQuotaSource(),
    ]
}
