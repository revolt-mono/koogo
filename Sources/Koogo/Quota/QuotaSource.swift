protocol QuotaSource: Sendable {
    func load() async -> QuotaReading
}

extension QuotaUnavailability {
    init(_ error: any Error) {
        self =
            switch error {
            case CommandLineTool.Failure.notFound: .binaryNotFound
            case CommandLineTool.Failure.timedOut: .timedOut
            default: .sessionFailed
            }
    }
}

extension EnumMap where Key == QuotaProvider, Value == any QuotaSource {
    init(codex: any QuotaSource, claude: any QuotaSource, grok: any QuotaSource) {
        self.init { provider in
            switch provider {
            case .codex: codex
            case .claude: claude
            case .grok: grok
            }
        }
    }
}
