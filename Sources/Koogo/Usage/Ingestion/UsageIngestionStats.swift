struct UsageIngestionStats: Sendable, Encodable {
    struct LogRoot: Equatable, Sendable, Encodable {
        let provider: Provider
        let path: String
        let exists: Bool
    }

    let logRoots: [LogRoot]
    let trackedFiles: [Provider: Int]
    let events: [Provider: Int]
    let malformedLines: [Provider: Int]
    let unpricedModels: [String]
}
