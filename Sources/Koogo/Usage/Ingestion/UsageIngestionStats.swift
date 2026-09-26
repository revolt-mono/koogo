/// How the last refresh went; the pipeline drops unparseable input silently,
/// so this is the only place ingestion health becomes observable.
struct UsageIngestionStats: Sendable, Encodable {
    struct LogRoot: Equatable, Sendable, Encodable {
        let provider: UsageProvider
        let path: String
        let exists: Bool
    }

    let logRoots: [LogRoot]
    let trackedFiles: [UsageProvider: Int]
    let events: [UsageProvider: Int]
    /// Lines in tracked files that parsers had to JSON-decode; the rest were ruled out from their bytes.
    /// A jump against the same logs usually means a prefilter stopped matching the provider's format.
    let decodedLines: [UsageProvider: Int]
    /// Lines in tracked files whose record kind the provider's parser knows but whose fields it cannot use;
    /// a nonzero count usually means the provider changed its log format.
    let malformedLines: [UsageProvider: Int]
    /// Model ids with events inside the history window that were dropped because the model,
    /// or one of its billed options (fast speed, US inference, cache writes, an unknown speed), has no price.
    let unpricedModels: [String]
}
