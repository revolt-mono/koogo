import Foundation

/// nil skips a log line; throwing counts the line as malformed; each line produces at most one outcome.
protocol UsageLogParser: Sendable {
    init()
    mutating func parse(_ line: UnsafeRawBufferPointer) throws -> UsageLineOutcome?
}

enum UsageLineOutcome: Sendable {
    case event(UsageEvent)
    case unpricedModel(ModelID, timestamp: Date)
}

struct MalformedUsageRecord: Error {}

struct UsageQuote: Sendable {
    let model: ModelID
    let cost: Picodollars
}
