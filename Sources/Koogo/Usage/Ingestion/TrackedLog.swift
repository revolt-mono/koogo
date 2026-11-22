import Foundation

protocol TrackedLog: Sendable {
  var events: UsageEventIndex { get }
  var droppedInput: DroppedInput { get }

  mutating func sync(observed metadata: UsageFileMetadata, since windowStart: UsageTimestamp)
  mutating func discard(before windowStart: UsageTimestamp)
}

struct ParsedLog<Parser: UsageLogParser>: TrackedLog {
  init?(_ file: any LogFile, since windowStart: UsageTimestamp) {
    self.file = file
    guard read(since: windowStart) else {
      return nil
    }
  }

  private(set) var events = UsageEventIndex()
  private(set) var droppedInput = DroppedInput()

  mutating func sync(observed metadata: UsageFileMetadata, since windowStart: UsageTimestamp) {
    if file.observe(metadata) {
      read(since: windowStart)
    }
  }

  mutating func discard(before windowStart: UsageTimestamp) {
    events.discard(before: windowStart)
    droppedInput.discard(before: windowStart)
  }

  private var file: any LogFile
  private var parser = Parser()

  @discardableResult
  private mutating func read(since windowStart: UsageTimestamp) -> Bool {
    events.update { batch in
      file.read(
        restart: {
          parser = Parser()
          batch.removeAll()
          droppedInput = DroppedInput()
        },
        consume: { line in
          do {
            switch try parser.parse(line) {
            case .event(let event) where event.record.timestamp >= windowStart:
              batch.insert(event)
            case .unpricedModel(let model, let timestamp) where timestamp >= windowStart:
              droppedInput.noteUnpricedModel(model, at: timestamp)
            case .event,
                 .unpricedModel,
                 nil:
              break
            }
          } catch {
            droppedInput.noteMalformedLine()
          }
        },
      )
    }
  }
}
