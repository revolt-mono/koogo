import Foundation

struct PiUsageLogParser: UsageLogParser {
  func parse(_ line: UnsafeRawBufferPointer) throws -> UsageLineOutcome? {
    guard
      let entry = try PiEntry(line),
      let billed = entry.billed,
      billed.processedTokens > 0 || billed.cost > .zero
    else {
      return nil
    }
    return .event(
      UsageEvent(
        id: .piAgent(entryID: entry.id, timestamp: billed.timestamp),
        record: UsageRecord(
          timestamp: billed.timestamp,
          processedTokens: billed.processedTokens,
          cost: billed.cost,
          model: billed.model,
        ),
      )
    )
  }
}

private struct PiEntry {
  init?(_ line: UnsafeRawBufferPointer) throws {
    guard var record = JSONObjectReader(line) else {
      return nil
    }
    var type: JSONValue?
    var id: JSONValue?
    var timestamp: JSONValue?
    var message: JSONValue?
    var provider: JSONValue?
    var model: JSONValue?
    var usage: JSONValue?
    while let member = try record.next() {
      switch member.key {
      case "type": type = member.value
      case "id": id = member.value
      case "timestamp": timestamp = member.value
      case "message": message = member.value
      case "provider": provider = member.value
      case "model": model = member.value
      case "usage": usage = member.value
      default: break
      }
    }
    guard let type, let id = try id?.text() else {
      throw MalformedUsageRecord()
    }
    let timestampText = try timestamp?.text()
    self.id = id
    switch type {
    case "message":
      guard let message else {
        throw MalformedUsageRecord()
      }
      billed = try PiBilledEntry(message: message)

    case "compaction",
         "branch_summary":
      billed = try usage?.nonNull.map {
        try PiBilledEntry(usage: $0, model: nil, timestamp: timestampText.flatMap(Date.init(iso8601:)))
      }

    // usage entries bill model calls outside the conversation, such as cache warming.
    case "usage":
      guard let usage, let providerName = try provider?.string(), let modelName = try model?.string() else {
        throw MalformedUsageRecord()
      }
      billed = try PiBilledEntry(
        usage: usage,
        model: PiModelCatalog.modelID(provider: providerName, model: modelName),
        timestamp: timestampText.flatMap(Date.init(iso8601:)),
      )

    default:
      billed = nil
    }
  }

  let id: JSONText
  let billed: PiBilledEntry?
}

private struct PiBilledEntry {
  init(usage: JSONValue, model: ModelID?, timestamp: Date?) throws {
    var processedTokens: JSONValue?
    var cost: JSONValue?
    var fields = try usage.object()
    while let member = try fields.next() {
      switch member.key {
      case "totalTokens": processedTokens = member.value
      case "cost": cost = member.value
      default: break
      }
    }
    guard
      let processedTokens = try processedTokens?.uint64(),
      let cost = try cost?.member("total")?.usd(),
      let timestamp
    else {
      throw MalformedUsageRecord()
    }
    self.processedTokens = processedTokens
    self.cost = cost
    self.model = model
    self.timestamp = timestamp
  }

  init?(message: JSONValue) throws {
    var role: JSONValue?
    var provider: JSONValue?
    var model: JSONValue?
    var milliseconds: JSONValue?
    var usage: JSONValue?
    var fields = try message.object()
    while let member = try fields.next() {
      switch member.key {
      case "role": role = member.value
      case "provider": provider = member.value
      case "model": model = member.value
      case "timestamp": milliseconds = member.value
      case "usage": usage = member.value
      default: break
      }
    }
    let providerName = try provider?.string()
    let modelName = try model?.string()
    guard let role else {
      throw MalformedUsageRecord()
    }
    guard let usage else {
      return nil
    }
    let reference: ModelID?
    switch role {
    case "assistant":
      guard let providerName, let modelName else {
        throw MalformedUsageRecord()
      }
      reference = PiModelCatalog.modelID(provider: providerName, model: modelName)

    case "toolResult":
      reference = nil

    default:
      return nil
    }
    let timestamp = try milliseconds?.uint64().map(Date.init(unixMilliseconds:))
    guard let usage = usage.nonNull else {
      return nil
    }
    try self.init(usage: usage, model: reference, timestamp: timestamp)
  }

  let processedTokens: UInt64
  let cost: Picodollars
  let model: ModelID?
  let timestamp: Date
}

extension UsageEventID {
  /// pi entry ids are eight hex digits unique only within a session; forks copy entries with their timestamps.
  static func piAgent(entryID: some Collection<UInt8>, timestamp: Date) -> Self {
    Self(.piAgent) {
      $0.combine(text: entryID)
      $0.combine(timestamp)
    }
  }
}
