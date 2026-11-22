import Foundation

struct ClaudeUsageLogParser: UsageLogParser {
  func parse(_ line: UnsafeRawBufferPointer) throws(MalformedUsageRecord) -> UsageLineOutcome? {
    guard let reply = try ClaudeAssistantReply(line) else {
      return nil
    }
    let usage = reply.usage.billable
    // claude logs synthetic replies such as api errors with zero usage and often no request id.
    guard usage.tokens.processed > 0 || usage.webSearchRequests > 0 else {
      return nil
    }
    guard
      let messageID = try reply.messageID?.text(),
      !messageID.isEmpty,
      let requestID = try reply.requestID?.text(),
      !requestID.isEmpty,
      let model = try reply.model?.string()?.nonEmpty.map(ModelID.init(rawValue:)),
      let timestamp = try reply.timestamp?.iso8601()
    else {
      throw MalformedUsageRecord()
    }
    guard let quote = ClaudeUsagePricing.quote(model: model, usage: usage) else {
      return .unpricedModel(model, timestamp: timestamp)
    }

    return .event(
      UsageEvent(
        id: .claude(messageID: messageID, requestID: requestID),
        record: UsageRecord(
          timestamp: timestamp,
          processedTokens: usage.tokens.processed,
          cost: quote.cost,
          model: quote.model,
        ),
        revision: reply.usage.revision,
      )
    )
  }
}

struct ClaudeTokenUsage: Sendable {
  init?(
    input: UInt64,
    cacheRead: UInt64,
    cacheCreation: CacheCreation,
    output: UInt64,
  ) {
    guard let processed = cacheCreation.tokens?.checkedAdding(input)?.checkedAdding(cacheRead)?.checkedAdding(output)
    else {
      return nil
    }
    self.input = input
    self.cacheRead = cacheRead
    self.cacheCreation = cacheCreation
    self.output = output
    self.processed = processed
  }

  enum CacheCreation: Sendable {
    case aggregate(UInt64)
    case byDuration(fiveMinute: UInt64, oneHour: UInt64)

    var tokens: UInt64? {
      switch self {
      case .aggregate(let tokens): tokens
      case .byDuration(let fiveMinute, let oneHour): fiveMinute.checkedAdding(oneHour)
      }
    }
  }

  let input: UInt64
  let cacheRead: UInt64
  let cacheCreation: CacheCreation
  let output: UInt64
  let processed: UInt64
}

struct ClaudeBillableUsage: Sendable {
  struct Options: OptionSet, Sendable {
    static let fastMode = Self(rawValue: 1 << 0)
    static let usInference = Self(rawValue: 1 << 1)

    let rawValue: UInt8
  }

  let tokens: ClaudeTokenUsage
  let options: Options?
  let webSearchRequests: UInt64
}

/// claude logs the kind after the message.
private struct ClaudeAssistantReply {
  init?(_ line: UnsafeRawBufferPointer) throws(MalformedUsageRecord) {
    guard var record = JSONObjectReader(line) else {
      return nil
    }
    var isAssistant = false
    var timestamp: JSONValue?
    var requestID: JSONValue?
    var message: JSONValue?
    while let member = try record.next() {
      switch member.key {
      case "type":
        guard member.value.isString("assistant") else {
          return nil
        }
        isAssistant = true

      case "timestamp": timestamp = member.value

      case "requestId": requestID = member.value

      case "message": message = member.value

      default: break
      }
    }
    guard isAssistant, let message else {
      return nil
    }

    var messageID: JSONValue?
    var model: JSONValue?
    var usage: JSONValue?
    var fields = try message.object()
    while let member = try fields.next() {
      switch member.key {
      case "id": messageID = member.value
      case "model": model = member.value
      case "usage": usage = member.value
      default: break
      }
    }
    guard let usage = try usage.map(ClaudeLoggedUsage.init) else {
      return nil
    }
    self.timestamp = timestamp
    self.requestID = requestID
    self.messageID = messageID
    self.model = model
    self.usage = usage
  }

  let timestamp: JSONValue?
  let requestID: JSONValue?
  let messageID: JSONValue?
  let model: JSONValue?
  let usage: ClaudeLoggedUsage
}

private struct ClaudeLoggedUsage {
  init(_ value: JSONValue) throws(MalformedUsageRecord) {
    var input: JSONValue?
    var cacheRead: JSONValue?
    var cacheCreationTotal: JSONValue?
    var cacheCreationSplit: JSONValue?
    var output: JSONValue?
    var speed: JSONValue?
    var geo: JSONValue?
    var serverToolUse: JSONValue?
    var fields = try value.object()
    while let member = try fields.next() {
      switch member.key {
      case "input_tokens": input = member.value
      case "cache_read_input_tokens": cacheRead = member.value
      case "cache_creation_input_tokens": cacheCreationTotal = member.value
      case "cache_creation": cacheCreationSplit = member.value
      case "output_tokens": output = member.value
      case "speed": speed = member.value
      case "inference_geo": geo = member.value
      case "server_tool_use": serverToolUse = member.value
      default: break
      }
    }
    guard
      let input = try input?.uint64(),
      let output = try output?.uint64(),
      let tokens = ClaudeTokenUsage(
        input: input,
        cacheRead: try cacheRead?.uint64() ?? 0,
        cacheCreation: try Self.cacheCreation(
          total: try cacheCreationTotal?.uint64() ?? 0,
          split: cacheCreationSplit?.nonNull,
        ),
        output: output,
      )
    else {
      throw MalformedUsageRecord()
    }
    let loggedSpeed = try speed?.string()
    billable = ClaudeBillableUsage(
      tokens: tokens,
      options: Self.options(speed: loggedSpeed, geo: try geo?.string()),
      webSearchRequests: try serverToolUse?.nonNull?.member("web_search_requests")?.uint64() ?? 0,
    )
    let explicitCacheDuration: UInt8 =
      if case .byDuration = tokens.cacheCreation {
        1
      } else {
        0
      }
    revision = UsageEvent.Revision(
      outputTokens: output,
      metadataCompleteness: (loggedSpeed == nil ? 0 : 1) + explicitCacheDuration,
    )
  }

  let billable: ClaudeBillableUsage
  let revision: UsageEvent.Revision

  private static func options(speed: String?, geo: String?) -> ClaudeBillableUsage.Options? {
    let region: ClaudeBillableUsage.Options = geo == "us" ? .usInference : []
    return switch speed {
    case nil,
         "standard": region
    case "fast": region.union(.fastMode)
    default: nil
    }
  }

  private static func cacheCreation(
    total: UInt64,
    split: JSONValue?,
  ) throws(MalformedUsageRecord) -> ClaudeTokenUsage.CacheCreation {
    guard let split else {
      return .aggregate(total)
    }
    var fiveMinute: JSONValue?
    var oneHour: JSONValue?
    var fields = try split.object()
    while let member = try fields.next() {
      switch member.key {
      case "ephemeral_5m_input_tokens": fiveMinute = member.value
      case "ephemeral_1h_input_tokens": oneHour = member.value
      default: break
      }
    }
    let byDuration = ClaudeTokenUsage.CacheCreation.byDuration(
      fiveMinute: try fiveMinute?.uint64() ?? 0,
      oneHour: try oneHour?.uint64() ?? 0,
    )
    guard byDuration.tokens == total else {
      throw MalformedUsageRecord()
    }
    return byDuration
  }
}

extension UsageEventID {
  fileprivate static func claude(messageID: JSONText, requestID: JSONText) -> Self {
    Self(.claude) {
      $0.combine(text: messageID)
      $0.combine(text: requestID)
    }
  }
}
