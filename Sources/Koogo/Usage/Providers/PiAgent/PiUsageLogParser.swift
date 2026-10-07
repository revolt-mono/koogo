import Foundation

struct PiUsageLogParser: UsageLogParser {
    private var thinkingByEntry: [String: String] = [:]

    mutating func parse(_ line: UnsafeRawBufferPointer) throws -> UsageLineOutcome? {
        guard let entry = try PiEntry(line) else {
            return nil
        }
        let thinking = entry.thinkingLevel ?? entry.parentID.flatMap { thinkingByEntry[$0] }
        if let thinking {
            thinkingByEntry[entry.id] = thinking
        }
        guard let billed = entry.billed, billed.model != nil || billed.processedTokens > 0 || billed.costUSD > 0
        else {
            return nil
        }
        return .event(
            UsageEvent(
                id: .piAgent(entryID: entry.id),
                record: UsageRecord(
                    timestamp: billed.timestamp,
                    processedTokens: billed.processedTokens,
                    costUSD: billed.costUSD,
                    modelTurn: billed.model.map { UsageRecord.ModelTurn(model: $0, reasoningEffort: thinking) }
                )
            )
        )
    }
}

private struct PiEntry {
    let id: String
    let parentID: String?
    let thinkingLevel: String?
    let billed: PiBilledEntry?

    init?(_ line: UnsafeRawBufferPointer) throws {
        guard let record = JSONValue(object: line) else {
            return nil
        }
        let (type, id, parentID, timestamp, thinkingLevel, message, usage) = try record.fields(
            .value("type"),
            .string("id"),
            .string("parentId"),
            .string("timestamp"),
            .value("thinkingLevel"),
            .value("message"),
            .value("usage")
        )
        guard let type, let id else {
            throw MalformedUsageRecord()
        }
        self.id = id
        self.parentID = parentID
        switch type {
        case "thinking_level_change":
            guard let level = try thinkingLevel?.string() else {
                throw MalformedUsageRecord()
            }
            self.thinkingLevel = level
            billed = nil
        case "message":
            guard let message else {
                throw MalformedUsageRecord()
            }
            self.thinkingLevel = nil
            billed = try PiBilledEntry(message: message)
        case "compaction", "branch_summary":
            self.thinkingLevel = nil
            billed = try usage.flatMap {
                try PiBilledEntry(usage: $0, model: nil, timestamp: timestamp.flatMap(Date.init(iso8601:)))
            }
        default:
            self.thinkingLevel = nil
            billed = nil
        }
    }
}

private struct PiBilledEntry {
    let processedTokens: UInt64
    let costUSD: Decimal
    let model: ModelID?
    let timestamp: Date

    init?(usage: JSONValue, model: ModelID?, timestamp: Date?) throws {
        guard let usage = usage.nonNull else {
            return nil
        }
        let (processedTokens, costUSD) = try usage.fields(
            .uint64("totalTokens"),
            JSONField("cost") { try $0.fields(.decimal("total")) }
        )
        guard let processedTokens, let costUSD, costUSD >= 0, let timestamp else {
            throw MalformedUsageRecord()
        }
        self.processedTokens = processedTokens
        self.costUSD = costUSD
        self.model = model
        self.timestamp = timestamp
    }

    init?(message: JSONValue) throws {
        let (role, provider, model, milliseconds, usage) = try message.fields(
            .value("role"),
            .string("provider"),
            .string("model"),
            .value("timestamp"),
            .value("usage")
        )
        guard let role else {
            throw MalformedUsageRecord()
        }
        guard let usage else {
            return nil
        }
        let reference: ModelID?
        switch role {
        case "assistant":
            guard let provider, let model else {
                throw MalformedUsageRecord()
            }
            reference = PiModelCatalog.modelID(provider: provider, model: model)
        case "toolResult":
            reference = nil
        default:
            return nil
        }
        let timestamp = try milliseconds?.integer(UInt64.self).map(Date.init(unixMilliseconds:))
        try self.init(usage: usage, model: reference, timestamp: timestamp)
    }
}
