import Foundation

protocol TrackedLog: Sendable {
  var events: UsageEventIndex { get }
  var tally: LogTally { get }

  mutating func sync(observed metadata: UsageFileMetadata, since windowStart: Date)
  mutating func discard(before windowStart: Date)
}

struct ParsedLog<Parser: UsageLogParser>: TrackedLog {
  init?(_ file: any LogFile, since windowStart: Date) {
    self.file = file
    guard read(since: windowStart) else {
      return nil
    }
  }

  private(set) var events = UsageEventIndex()
  private(set) var tally = LogTally()

  mutating func sync(observed metadata: UsageFileMetadata, since windowStart: Date) {
    if file.observe(metadata) {
      read(since: windowStart)
    }
  }

  mutating func discard(before windowStart: Date) {
    events.discard(before: windowStart)
    tally.discard(before: windowStart)
  }

  private var file: any LogFile
  private var parser = Parser()

  @discardableResult
  private mutating func read(since windowStart: Date) -> Bool {
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
            case .event,
                 .unpricedModel,
                 nil:
              break
            }
          } catch {
            tally.noteMalformedLine()
          }
        },
      )
    }
  }
}
