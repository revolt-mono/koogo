import Foundation

/// One provider's logs on disk: where they live, how each file is read, and any provider-wide
/// state the parsed events depend on. The index owns one instance per provider.
protocol UsageLogSource: Sendable {
    /// The directory the provider creates when installed, relative to the user's home, such as `.codex`.
    var homePath: String { get }
    /// Log roots under the provider home, in report order.
    var logDirectories: [String] { get }

    /// Reloads provider-wide state under `home` and returns whether the tracked logs must be read again
    /// because their events would now parse differently.
    mutating func refresh(home: URL) -> Bool

    /// Opens a `.jsonl` file found under a log root, or nil for a file that is not a usage log; a rejected
    /// path is offered again on the next scan.
    func openLog(at url: URL, since historyStart: Date) -> (any UsageLog)?
}

extension UsageLogSource {
    mutating func refresh(home: URL) -> Bool {
        false
    }
}

/// What the index tracks for each admitted log path.
protocol UsageLog: Sendable {
    var events: UsageEventIndex { get }
    var malformedLines: Int { get }
    /// Returns whether the log changed on disk since the last pass.
    mutating func refresh(observed metadata: UsageFileMetadata) -> Bool
    mutating func discard(before historyStart: Date)
}

/// One line-oriented log format. Parsers carry per-file state such as the current Codex turn,
/// so each tracked file owns its own instance.
protocol UsageLogParser: Sendable {
    /// Returns `nil` for a line that bills nothing, and throws for a line of a record kind the
    /// parser knows whose fields it cannot use. Parsers read a line's members in place with
    /// `JSONObjectReader`, so a record they rule out by kind costs only the bytes before its kind.
    mutating func parse(_ line: UnsafeRawBufferPointer) throws -> UsageLineOutcome?
}

/// A known record kind with missing or invalid fields.
struct MalformedUsageRecord: Error {}
