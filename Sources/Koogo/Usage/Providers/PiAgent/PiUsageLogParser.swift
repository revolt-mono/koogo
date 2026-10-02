import Foundation

struct PiLogParser: UsageLogParser {
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
        guard var record = JSONObjectReader(line) else {
            return nil
        }
        var type: JSONValue?
        var id: String?
        var parentID: String?
        var timestamp: String?
        var thinkingLevel: JSONValue?
        var message: JSONValue?
        var usage: JSONValue?
        while let member = try record.next() {
            switch member.key {
            case "type": type = member.value
            case "id": id = try member.value.string()
            case "parentId": parentID = try member.value.string()
            case "timestamp": timestamp = try member.value.string()
            case "thinkingLevel": thinkingLevel = member.value
            case "message": message = member.value
            case "usage": usage = member.value
            default: continue
            }
        }
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
        guard var usage = try usage.nonNull?.object() else {
            return nil
        }
        var processedTokens: UInt64?
        var costUSD: Decimal?
        while let member = try usage.next() {
            switch member.key {
            case "totalTokens": processedTokens = try member.value.integer()
            case "cost": costUSD = try member.value.member("total")?.decimal()
            default: continue
            }
        }
        guard let processedTokens, let costUSD, costUSD >= 0, let timestamp else {
            throw MalformedUsageRecord()
        }
        self.processedTokens = processedTokens
        self.costUSD = costUSD
        self.model = model
        self.timestamp = timestamp
    }

    init?(message: JSONValue) throws {
        var message = try message.object()
        var role: JSONValue?
        var provider: String?
        var model: String?
        var milliseconds: JSONValue?
        var usage: JSONValue?
        while let member = try message.next() {
            switch member.key {
            case "role": role = member.value
            case "provider": provider = try member.value.string()
            case "model": model = try member.value.string()
            case "timestamp": milliseconds = member.value
            case "usage": usage = member.value
            default: continue
            }
        }
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
        let timestamp = try milliseconds?.integer(UInt64.self).map {
            Date(timeIntervalSince1970: TimeInterval($0) / 1_000)
        }
        try self.init(usage: usage, model: reference, timestamp: timestamp)
    }
}
