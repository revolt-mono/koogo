import Foundation

/// each completed grok turn sums the whole prompt per model, including subagents.
struct GrokUsageLogParser: UsageLogParser {
  func parse(_ line: UnsafeRawBufferPointer) throws(MalformedUsageRecord) -> UsageLineOutcome? {
    guard let turn = try GrokCompletedTurn(line) else {
      return nil
    }
    let timestamp = UsageTimestamp(unixMilliseconds: turn.milliseconds)
    let prompt = turn.prompt
    guard !prompt.modelUsage.isEmpty else {
      // cancelled grok prompts can complete with no model rows and zero billable tokens.
      guard prompt.totalTokens == 0 else { throw MalformedUsageRecord() }
      return nil
    }
    var cost = Picodollars.zero
    for (model, tokens) in prompt.modelUsage {
      guard let modelCost = GrokUsagePricing.cost(of: tokens, model: model) else {
        return .unpricedModel(model, timestamp: timestamp)
      }
      cost += modelCost
    }

    return .event(
      UsageEvent(
        id: .grok(eventID: turn.eventID, timestampMilliseconds: turn.milliseconds),
        record: UsageRecord(
          timestamp: timestamp,
          processedTokens: prompt.totalTokens,
          cost: cost,
          model: nil,
        ),
      )
    )
  }
}

private struct GrokCompletedTurn {
  init?(_ line: UnsafeRawBufferPointer) throws(MalformedUsageRecord) {
    guard
      let params = try JSONObjectReader(line)?.member("params"),
      let update = try params.member("update"),
      let usage = try Self.completedTurnUsage(in: update)
    else {
      return nil
    }
    guard
      let meta = try params.member("_meta"),
      let eventID = try meta.member("eventId")?.text(),
      let milliseconds = try meta.member("agentTimestampMs")?.uint64()
    else {
      throw MalformedUsageRecord()
    }
    self.eventID = eventID
    self.milliseconds = milliseconds
    prompt = try GrokPromptUsage(usage)
  }

  let eventID: JSONText
  let milliseconds: UInt64
  let prompt: GrokPromptUsage

  private static func completedTurnUsage(in update: JSONValue) throws(MalformedUsageRecord) -> JSONValue? {
    var isCompletedTurn = false
    var usage: JSONValue?
    var fields = try update.object()
    while let member = try fields.next() {
      switch member.key {
      case "sessionUpdate":
        guard member.value.isString("turn_completed") else {
          return nil
        }
        isCompletedTurn = true

      case "usage": usage = member.value

      default: break
      }
    }
    return isCompletedTurn ? usage?.nonNull : nil
  }
}

private struct GrokPromptUsage {
  init(_ value: JSONValue) throws(MalformedUsageRecord) {
    var totalTokens: JSONValue?
    var modelUsage: JSONValue?
    var fields = try value.object()
    while let member = try fields.next() {
      switch member.key {
      case "totalTokens": totalTokens = member.value
      case "modelUsage": modelUsage = member.value
      default: break
      }
    }
    guard let totalTokens = try totalTokens?.uint64() else {
      throw MalformedUsageRecord()
    }
    var models = try modelUsage?.object()
    var usage = [(model: ModelID, tokens: GrokTokenUsage)]()
    while let row = try models?.next() {
      usage.append((ModelID(rawValue: try row.key.string()), try GrokTokenUsage(row.value)))
    }
    self.totalTokens = totalTokens
    self.modelUsage = usage
  }

  /// prompt input including cache reads, plus output.
  let totalTokens: UInt64
  let modelUsage: [(model: ModelID, tokens: GrokTokenUsage)]
}

struct GrokTokenUsage: Sendable {
  init?(input: UInt64, cachedInput: UInt64, output: UInt64) {
    guard cachedInput <= input else {
      return nil
    }
    self.input = input
    self.cachedInput = cachedInput
    self.output = output
  }

  fileprivate init(_ value: JSONValue) throws(MalformedUsageRecord) {
    var input: JSONValue?
    var cachedInput: JSONValue?
    var output: JSONValue?
    var fields = try value.object()
    while let member = try fields.next() {
      switch member.key {
      case "inputTokens": input = member.value
      case "cachedReadTokens": cachedInput = member.value
      case "outputTokens": output = member.value
      default: break
      }
    }
    guard
      let input = try input?.uint64(),
      let cachedInput = try cachedInput?.uint64(),
      let output = try output?.uint64(),
      let usage = GrokTokenUsage(input: input, cachedInput: cachedInput, output: output)
    else {
      throw MalformedUsageRecord()
    }
    self = usage
  }

  let input: UInt64
  let cachedInput: UInt64
  let output: UInt64

  var uncachedInput: UInt64 {
    input - cachedInput
  }
}

extension UsageEventID {
  /// grok forks preserve both fields; resumed sessions can reuse an event id at a later time.
  fileprivate static func grok(eventID: JSONText, timestampMilliseconds: UInt64) -> Self {
    Self(.grok) {
      $0.combine(text: eventID)
      $0.combine(timestampMilliseconds)
    }
  }
}
