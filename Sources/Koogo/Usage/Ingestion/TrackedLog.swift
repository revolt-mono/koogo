import Foundation

/// One admitted log on disk, kept current between refreshes.
protocol TrackedLog: Sendable {
    var events: UsageEventIndex { get }
    var tally: LogTally { get }
    /// Reads what changed since the last sync. Returns true when events or the tally may differ.
    mutating func sync(observed metadata: UsageFileMetadata) -> Bool
    mutating func discard(before windowStart: Date)
}

/// What one parser has made of a log's lines: its running state, surviving events, and dropped lines.
struct ParsedLines<Parser: UsageLogParser>: LineConsumer, Sendable {
    private(set) var parser = Parser()
    var events = UsageEventIndex()
    private(set) var tally = LogTally()
    private var windowStart: Date

    init(since windowStart: Date) {
        self.windowStart = windowStart
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

/// A log whose every line goes through one parser.
struct ParsedLog<Parser: UsageLogParser>: TrackedLog {
    private var file: AppendOnlyFile
    private var lines: ParsedLines<Parser>

    var events: UsageEventIndex { lines.events }
    var tally: LogTally { lines.tally }

    init?(_ url: URL, since windowStart: Date) {
        guard let file = AppendOnlyFile(url) else {
            return nil
        }
        self.file = file
        lines = ParsedLines(since: windowStart)
        guard self.file.read(into: &lines) != .unreadable else {
            return nil
        }
    }

    mutating func sync(observed metadata: UsageFileMetadata) -> Bool {
        guard file.observe(metadata) else {
            return false
        }
        return file.read(into: &lines) != .nothingNew
    }

    mutating func discard(before windowStart: Date) {
        lines.discard(before: windowStart)
    }
}
