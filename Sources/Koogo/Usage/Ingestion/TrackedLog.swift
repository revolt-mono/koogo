import Foundation

protocol TrackedLog: Sendable {
    var events: UsageEventIndex { get }
    var tally: LogTally { get }
    /// Reads what changed since the last sync. Returns true when events or the tally may differ.
    mutating func sync(observed metadata: UsageFileMetadata) -> Bool
    mutating func discard(before windowStart: Date)
}

struct ParsedLog<Parser: UsageLogParser>: TrackedLog {
    private var file: AppendOnlyFile
    private var parser = Parser()
    private var windowStart: Date
    private(set) var events = UsageEventIndex()
    private(set) var tally = LogTally()

    init?(_ path: String, observed metadata: UsageFileMetadata, since windowStart: Date) {
        file = AppendOnlyFile(path, observed: metadata)
        self.windowStart = windowStart
        guard read() != .unreadable else {
            return nil
        }
    }

    mutating func sync(observed metadata: UsageFileMetadata) -> Bool {
        guard file.observe(metadata) else {
            return false
        }
        return read() == .readLines
    }

    mutating func discard(before windowStart: Date) {
        self.windowStart = windowStart
        events.discard(before: windowStart)
        tally.discard(before: windowStart)
    }

    private mutating func read() -> FileRead {
        events.update { batch in
            file.read(
                restart: {
                    parser = Parser()
                    batch.removeAll()
                    tally = LogTally()
                },
                consume: { line in
                    do {
                        switch try parser.parse(line) {
                        case .event(let event) where event.record.timestamp >= windowStart:
                            batch.insert(event)
                        case .unpricedModel(let id, let timestamp) where timestamp >= windowStart:
                            tally.noteUnpricedModel(id, at: timestamp)
                        case .event, .unpricedModel, nil:
                            break
                        }
                    } catch {
                        tally.noteMalformedLine()
                    }
                }
            )
        }
    }
}
