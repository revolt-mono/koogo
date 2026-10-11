import Foundation

struct PiUsageLogParser: UsageLogParser {
    private var levelSlots: [String: UInt8] = [:]
    private var levels: [String] = []

    mutating func parse(_ line: UnsafeRawBufferPointer) throws -> UsageLineOutcome? {
        guard let entry = try PiEntry(line) else {
            return nil
        }
        let levelSlot =
            if case .thinkingLevelChange(let level) = entry.kind {
                try slot(of: level)
            } else {
                entry.parentID.flatMap { levelSlots[$0] }
            }
        if let levelSlot {
            levelSlots[entry.id] = levelSlot
        }
        let thinking = levelSlot.map { levels[Int($0)] }
        guard case .billed(let billed) = entry.kind,
            billed.model != nil || billed.processedTokens > 0 || billed.costUSD > 0
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

    /// A log naming more distinct levels than a slot can hold is malformed.
    private mutating func slot(of level: String) throws -> UInt8 {
        if let slot = levels.firstIndex(of: level) {
            return UInt8(slot)
        }
        guard let slot = UInt8(exactly: levels.count) else {
            throw MalformedUsageRecord()
        }
        levels.append(level)
        return slot
    }
}

private struct PiEntry {
    enum Kind {
        case thinkingLevelChange(String)
        case billed(PiBilledEntry)
        case other
    }

    let id: String
    let parentID: String?
    let kind: Kind

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
            kind = .thinkingLevelChange(level)
        case "message":
            guard let message else {
                throw MalformedUsageRecord()
            }
            kind = try PiBilledEntry(message: message).map(Kind.billed) ?? .other
        case "compaction", "branch_summary":
            kind =
                try usage.flatMap {
                    try PiBilledEntry(usage: $0, model: nil, timestamp: timestamp.flatMap(Date.init(iso8601:)))
                }
                .map(Kind.billed) ?? .other
        default:
            kind = .other
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
