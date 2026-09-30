import Foundation

protocol UsageLogSource: Sendable {
    var homePath: String { get }
    var logDirectories: [String] { get }
    var logFileSuffix: String { get }

    mutating func refresh(home: URL) -> Bool

    func openLog(at url: URL, since historyStart: Date) -> (any UsageLog)?
}

extension UsageLogSource {
    var logFileSuffix: String {
        ".jsonl"
    }

    mutating func refresh(home: URL) -> Bool {
        false
    }
}

protocol UsageLog: Sendable {
    var events: UsageEventIndex { get }
    var malformedLines: Int { get }
    mutating func refresh(observed metadata: UsageFileMetadata) -> Bool
    mutating func discard(before historyStart: Date)
}

protocol UsageLogParser: Sendable {
    mutating func parse(_ line: UnsafeRawBufferPointer) throws -> UsageLineOutcome?
}

struct MalformedUsageRecord: Error {}
