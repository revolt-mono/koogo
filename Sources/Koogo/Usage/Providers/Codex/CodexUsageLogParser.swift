import Foundation

/// codex writes one `token_usage_record` per completed response; the preceding `turn_context` names the model.
struct CodexUsageLogParser: UsageLogParser {
  mutating func parse(_ line: UnsafeRawBufferPointer) throws -> UsageLineOutcome? {
    guard var record = JSONObjectReader(line) else {
      return nil
    }
    var kind: RecordKind?
    var timestamp: JSONValue?
    var payload: JSONValue?
    while let member = try record.next() {
      switch member.key {
      case "type":
        guard let recordKind = RecordKind(member.value) else {
          return nil
        }
        kind = recordKind

      case "timestamp": timestamp = member.value

      case "payload": payload = member.value

      default: break
      }
    }
    switch kind {
    case nil:
      return nil

    case .turnContext:
      model = try? payload?.member("model")?.string()?.nonEmpty.map(ModelID.init(rawValue:))
      guard model != nil else {
        throw MalformedUsageRecord()
      }
      return nil

    case .tokenUsageRecord:
      guard let payload, let timestamp = try timestamp?.text().flatMap(Date.init(iso8601:)) else {
        throw MalformedUsageRecord()
      }
      let record = try CodexTokenUsageRecord(payload)
      guard let model else {
        return nil
      }
      guard let quote = CodexUsagePricing.quote(model: model, tokens: record.usage) else {
        return .unpricedModel(model, timestamp: timestamp)
      }
      return .event(
        UsageEvent(
          id: .codex(responseID: record.responseID),
          record: UsageRecord(
            timestamp: timestamp,
            processedTokens: record.usage.processed,
            cost: quote.cost,
            model: quote.model,
          ),
        )
      )
    }
  }

  private enum RecordKind {
    case turnContext
    case tokenUsageRecord

    init?(_ value: JSONValue) {
      switch value {
      case "turn_context": self = .turnContext
      case "token_usage_record": self = .tokenUsageRecord
      default: return nil
      }
    }
  }

  private var model: ModelID?
}

private struct CodexTokenUsageRecord {
  init(_ payload: JSONValue) throws {
    var responseID: JSONValue?
    var usage: JSONValue?
    var fields = try payload.object()
    while let member = try fields.next() {
      switch member.key {
      case "response_id": responseID = member.value
      case "usage": usage = member.value
      default: break
      }
    }
    guard
      let responseID = try responseID?.text(),
      !responseID.isEmpty,
      let usage = try usage.map(CodexTokenUsage.init)
    else {
      throw MalformedUsageRecord()
    }
    self.responseID = responseID
    self.usage = usage
  }

  let responseID: JSONText
  let usage: CodexTokenUsage
}

struct CodexTokenUsage: Sendable {
  init?(input: UInt64, cachedInput: UInt64, cacheWrite: UInt64, output: UInt64, processed: UInt64) {
    guard let cachedAndWritten = cachedInput.checkedAdding(cacheWrite), cachedAndWritten <= input else {
      return nil
    }
    self.input = input
    self.cachedInput = cachedInput
    self.cacheWrite = cacheWrite
    self.output = output
    self.processed = processed
  }

  fileprivate init(_ value: JSONValue) throws {
    var input: JSONValue?
    var cachedInput: JSONValue?
    var cacheWrite: JSONValue?
    var output: JSONValue?
    var processed: JSONValue?
    var fields = try value.object()
    while let member = try fields.next() {
      switch member.key {
      case "input_tokens": input = member.value
      case "cached_input_tokens": cachedInput = member.value
      case "cache_write_input_tokens": cacheWrite = member.value
      case "output_tokens": output = member.value
      case "total_tokens": processed = member.value
      default: break
      }
    }
    guard
      let input = try input?.uint64(),
      let cachedInput = try cachedInput?.uint64(),
      let output = try output?.uint64(),
      let processed = try processed?.uint64(),
      let usage = CodexTokenUsage(
        input: input,
        cachedInput: cachedInput,
        cacheWrite: try cacheWrite?.uint64() ?? 0,
        output: output,
        processed: processed,
      )
    else {
      throw MalformedUsageRecord()
    }
    self = usage
  }

  let input: UInt64
  let cachedInput: UInt64
  let cacheWrite: UInt64
  let output: UInt64
  let processed: UInt64

  var uncachedInput: UInt64 {
    input - cachedInput - cacheWrite
  }
}

extension UsageEventID {
  /// codex forks change thread ids, ordinals, and timestamps; each copied record keeps its response id.
  static func codex(responseID: some Collection<UInt8>) -> Self {
    Self(.codex) { $0.combine(text: responseID) }
  }
}
