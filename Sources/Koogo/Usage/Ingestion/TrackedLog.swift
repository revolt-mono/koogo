import Foundation

/// One admitted log on disk, kept current between refreshes.
protocol TrackedLog: Sendable {
    var events: UsageEventIndex { get }
    var tally: LogTally { get }
    /// Reads what changed since the last sync. Returns true when events or the tally may differ.
    mutating func sync(observed metadata: UsageFileMetadata) -> Bool
    mutating func discard(before windowStart: Date)
}

struct ParsedLines<Parser: UsageLogParser>: LineConsumer, Sendable {
    private var parser = Parser()
    private(set) var events = UsageEventIndex()
    private(set) var tally = LogTally()
    private var windowStart: Date

    init(since windowStart: Date) {
        self.windowStart = windowStart
    }

    mutating func read(_ file: inout AppendOnlyFile) -> FileRead {
        let read = file.read(into: &self)
        events.seal()
        return read
    }

    mutating func restart() {
        parser = Parser()
        events = UsageEventIndex()
        tally = LogTally()
    }

    mutating func consume(_ line: UnsafeRawBufferPointer) {
        do {
            switch try parser.parse(line) {
            case .event(let event): events.insert(event, since: windowStart)
            case .unpricedModel(let id, let timestamp): tally.noteUnpricedModel(id, at: timestamp, since: windowStart)
            case nil: break
            }
        } catch {
            tally.countMalformedLines(1)
        }
    }

    mutating func discard(before windowStart: Date) {
        self.windowStart = windowStart
        events.discard(before: windowStart)
        tally.discard(before: windowStart)
    }
}

struct ParsedLog<Parser: UsageLogParser>: TrackedLog {
    private var file: AppendOnlyFile
    private var lines: ParsedLines<Parser>

    var events: UsageEventIndex { lines.events }
    var tally: LogTally { lines.tally }

    init?(_ path: String, since windowStart: Date) {
        guard let file = AppendOnlyFile(path) else {
            return nil
        }
        self.file = file
        lines = ParsedLines(since: windowStart)
        guard lines.read(&self.file) != .unreadable else {
            return nil
        }
    }

    mutating func sync(observed metadata: UsageFileMetadata) -> Bool {
        guard file.observe(metadata) else {
            return false
        }
        return lines.read(&file) != .nothingNew
    }

    mutating func discard(before windowStart: Date) {
        lines.discard(before: windowStart)
    }
}
