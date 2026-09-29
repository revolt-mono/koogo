/// One provider's line-oriented log format. Parsers carry per-file state such as
/// the current Codex turn, so each tracked file owns its own instance.
protocol UsageLogParser: Sendable {
    init()

    /// Returns `nil` for a line that bills nothing, and throws for a line of a record kind the
    /// parser knows whose fields it cannot use. Parsers read a line's members in place with
    /// `JSONObjectReader`, so a record they rule out by kind costs only the bytes before its kind.
    mutating func parse(_ line: UnsafeRawBufferPointer) throws -> UsageLineOutcome?
}

/// A known record kind with missing or invalid fields.
struct MalformedUsageRecord: Error {}
