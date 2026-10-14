import Foundation

struct PiUsageLogParser: UsageLogParser {
    func parse(_ line: UnsafeRawBufferPointer) throws -> UsageLineOutcome? {
        guard let entry = try PiEntry(line), let billed = entry.billed,
            billed.processedTokens > 0 || billed.cost > .zero
        else {
            return nil
        }
        return .event(
            UsageEvent(
                id: .piAgent(entryID: entry.id),
                record: UsageRecord(
                    timestamp: billed.timestamp,
                    processedTokens: billed.processedTokens,
                    cost: billed.cost,
                    model: billed.model
                )
            )
        )
    }
}

private struct PiEntry {
    let id: String
    let billed: PiBilledEntry?

    init?(_ line: UnsafeRawBufferPointer) throws {
        guard let record = JSONValue(object: line) else {
            return nil
        }
        let (type, id, timestamp, message, usage) = try record.fields(
            .value("type"),
            .string("id"),
            .string("timestamp"),
            .value("message"),
            .value("usage")
        )
        guard let type, let id else {
            throw MalformedUsageRecord()
        }
        self.id = id
        switch type {
        case "message":
            guard let message else {
                throw MalformedUsageRecord()
            }
            billed = try PiBilledEntry(message: message)
        case "compaction", "branch_summary":
            billed = try usage.flatMap {
                try PiBilledEntry(usage: $0, model: nil, timestamp: timestamp.flatMap(Date.init(iso8601:)))
            }
        default:
            billed = nil
        }
    }
}

private struct PiBilledEntry {
    let processedTokens: UInt64
    let cost: Picodollars
    let model: ModelID?
    let timestamp: Date

    init?(usage: JSONValue, model: ModelID?, timestamp: Date?) throws {
        guard let usage = usage.nonNull else {
            return nil
        }
        let (processedTokens, cost) = try usage.fields(
            .uint64("totalTokens"),
            JSONField("cost") { try $0.fields(.usd("total")) }
        )
        guard let processedTokens, let cost, let timestamp else {
            throw MalformedUsageRecord()
        }
        self.processedTokens = processedTokens
        self.cost = cost
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
        let timestamp = try milliseconds?.uint64().map(Date.init(unixMilliseconds:))
        try self.init(usage: usage, model: reference, timestamp: timestamp)
    }
}
