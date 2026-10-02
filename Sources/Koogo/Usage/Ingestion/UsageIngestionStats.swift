struct UsageIngestionStats: Sendable, Encodable {
    struct LogRoot: Equatable, Sendable, Encodable {
        let provider: Provider
        let path: String
        let exists: Bool
    }

    let logRoots: [LogRoot]
    let trackedFiles: EnumMap<Provider, Int>
    let events: EnumMap<Provider, Int>
    let malformedLines: EnumMap<Provider, Int>
    let unpricedModels: [String]
}
