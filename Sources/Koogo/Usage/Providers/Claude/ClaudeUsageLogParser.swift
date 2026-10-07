import Foundation

struct ClaudeUsageLogParser: UsageLogParser {
    func parse(_ line: UnsafeRawBufferPointer) throws -> UsageLineOutcome? {
        guard let reply = try ClaudeAssistantReply(line) else {
            return nil
        }
        let usage = reply.usage
        // Claude Code logs its own synthetic replies, such as API errors, with zero usage and often no request id.
        guard usage.tokens.processed > 0 || usage.webSearchRequests > 0 else {
            return nil
        }
        guard
            let timestamp = reply.timestamp.flatMap(Date.init(iso8601:)),
            let messageID = nonEmpty(reply.messageID),
            let requestID = nonEmpty(reply.requestID),
            let model = nonEmpty(reply.model)
        else {
            throw MalformedUsageRecord()
        }
        let isFast: Bool
        switch usage.speed {
        case nil, "standard": isFast = false
        case "fast": isFast = true
        default: return .unpricedModel(id: model, timestamp: timestamp)
        }
        let billable = ClaudeBillableUsage(
            tokens: usage.tokens,
            isFast: isFast,
            isUSInference: usage.geo == "us",
            webSearchRequests: usage.webSearchRequests
        )
        guard let quote = ClaudeUsagePricing.quote(model: model, usage: billable) else {
            return .unpricedModel(id: model, timestamp: timestamp)
        }

        let reasoningEffort = nonEmpty(reply.effort)
        return .event(
            UsageEvent(
                id: .claude(messageID: messageID, requestID: requestID),
                record: UsageRecord(
                    timestamp: timestamp,
                    processedTokens: usage.tokens.processed,
                    quote: quote,
                    reasoningEffort: reasoningEffort
                ),
                revision: Self.revision(of: usage, reasoningEffort: reasoningEffort)
            )
        )
    }

    private static func revision(of usage: ClaudeLoggedUsage, reasoningEffort: String?) -> UsageEvent.Revision {
        let explicitCacheDuration =
            switch usage.tokens.cacheCreation {
            case .aggregate: 0
            case .byDuration: 1
            }
        return UsageEvent.Revision(
            outputTokens: usage.tokens.output,
            metadataCompleteness: (usage.speed == nil ? 0 : 1)
                + explicitCacheDuration
                + (reasoningEffort == nil ? 0 : 1)
        )
    }
}

struct ClaudeTokenUsage: Sendable {
    enum CacheCreation: Sendable {
        case aggregate(UInt64)
        case byDuration(fiveMinute: UInt64, oneHour: UInt64)
    }

    let input: UInt64
    let cacheRead: UInt64
    let cacheCreation: CacheCreation
    let output: UInt64
    let processed: UInt64

    init?(
        input: UInt64,
        cacheRead: UInt64,
        cacheCreation: CacheCreation,
        output: UInt64
    ) {
        let cacheCreated =
            switch cacheCreation {
            case .aggregate(let tokens): Optional(tokens)
            case .byDuration(let fiveMinute, let oneHour): fiveMinute.checkedAdding(oneHour)
            }
        guard let processed = cacheCreated?.checkedAdding(input)?.checkedAdding(cacheRead)?.checkedAdding(output) else {
            return nil
        }
        self.input = input
        self.cacheRead = cacheRead
        self.cacheCreation = cacheCreation
        self.output = output
        self.processed = processed
    }
}

struct ClaudeBillableUsage: Sendable {
    let tokens: ClaudeTokenUsage
    let isFast: Bool
    let isUSInference: Bool
    let webSearchRequests: UInt64
}

private struct ClaudeAssistantReply {
    let timestamp: String?
    let requestID: String?
    let effort: String?
    let messageID: String?
    let model: String?
    let usage: ClaudeLoggedUsage

    init?(_ line: UnsafeRawBufferPointer) throws {
        guard let record = JSONValue(object: line) else {
            return nil
        }
        let (kind, timestamp, requestID, effort, message) = try record.fields(
            .kind("type") { $0.isString("assistant") },
            .string("timestamp"),
            .string("requestId"),
            .string("effort"),
            .value("message")
        )
        guard kind != nil, let message else {
            return nil
        }
        let (messageID, model, usage) = try message.fields(
            .string("id"),
            .string("model"),
            JSONField("usage", ClaudeLoggedUsage.init)
        )
        guard let usage else {
            return nil
        }
        self.timestamp = timestamp
        self.requestID = requestID
        self.effort = effort
        self.messageID = messageID
        self.model = model
        self.usage = usage
    }
}

private struct ClaudeLoggedUsage {
    let tokens: ClaudeTokenUsage
    let speed: String?
    let geo: String?
    let webSearchRequests: UInt64

    init(_ value: JSONValue) throws {
        let (input, cacheRead, cacheCreationTotal, cacheCreationSplit, output, speed, geo, serverToolUse) =
            try value.fields(
                .uint64("input_tokens"),
                .uint64("cache_read_input_tokens"),
                .uint64("cache_creation_input_tokens"),
                .value("cache_creation"),
                .uint64("output_tokens"),
                .string("speed"),
                .string("inference_geo"),
                .value("server_tool_use")
            )
        guard let input, let output,
            let tokens = ClaudeTokenUsage(
                input: input,
                cacheRead: cacheRead ?? 0,
                cacheCreation: try Self.cacheCreation(
                    total: cacheCreationTotal ?? 0,
                    split: cacheCreationSplit?.nonNull
                ),
                output: output
            )
        else {
            throw MalformedUsageRecord()
        }
        self.tokens = tokens
        self.speed = speed
        self.geo = geo
        webSearchRequests = try serverToolUse?.nonNull?.fields(.uint64("web_search_requests")) ?? 0
    }

    private static func cacheCreation(total: UInt64, split: JSONValue?) throws -> ClaudeTokenUsage.CacheCreation {
        guard let split else {
            return .aggregate(total)
        }
        let (fiveMinute, oneHour) = try split.fields(
            .uint64("ephemeral_5m_input_tokens"),
            .uint64("ephemeral_1h_input_tokens")
        )
        guard (fiveMinute ?? 0).checkedAdding(oneHour ?? 0) == total else {
            throw MalformedUsageRecord()
        }
        return .byDuration(fiveMinute: fiveMinute ?? 0, oneHour: oneHour ?? 0)
    }
}

private func nonEmpty(_ value: String?) -> String? {
    guard let value, !value.isEmpty else {
        return nil
    }
    return value
}
