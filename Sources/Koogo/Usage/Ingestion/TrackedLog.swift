import Foundation

protocol TrackedLog: Sendable {
    var events: UsageEventIndex { get }
    var tally: LogTally { get }
    mutating func sync(observed metadata: UsageFileMetadata)
    mutating func discard(before windowStart: Date)
}

struct ParsedLog<Parser: UsageLogParser>: TrackedLog {
    private var file: any LogFile
    private var parser = Parser()
    private var windowStart: Date
    private(set) var events = UsageEventIndex()
    private(set) var tally = LogTally()

    init?(_ file: any LogFile, since windowStart: Date) {
        self.file = file
        self.windowStart = windowStart
        guard read() else {
            return nil
        }
    }

    mutating func sync(observed metadata: UsageFileMetadata) {
        if file.observe(metadata) {
            read()
        }
    }

    mutating func discard(before windowStart: Date) {
        self.windowStart = windowStart
        events.discard(before: windowStart)
        tally.discard(before: windowStart)
    }

    @discardableResult
    private mutating func read() -> Bool {
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
