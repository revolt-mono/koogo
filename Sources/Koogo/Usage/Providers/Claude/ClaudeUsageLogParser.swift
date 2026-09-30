import Foundation

struct ClaudeLogParser: UsageLogParser {
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
                key: .claude(messageID: messageID, requestID: requestID),
                usage: UsageRecord(
                    timestamp: timestamp,
                    processedTokens: usage.tokens.processed,
                    costUSD: quote.costUSD,
                    modelTurn: UsageRecord.ModelTurn(
                        model: quote.model,
                        reasoningEffort: reasoningEffort
                    )
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

private struct ClaudeAssistantReply {
    let timestamp: String?
    let requestID: String?
    let effort: String?
    let messageID: String?
    let model: String?
    let usage: ClaudeLoggedUsage

    init?(_ line: UnsafeRawBufferPointer) throws {
        guard var record = JSONObjectReader(line) else {
            return nil
        }
        var isAssistant = false
        var timestamp: String?
        var requestID: String?
        var effort: String?
        var message: JSONValue?
        while let member = try record.next() {
            switch member.key {
            case "type":
                guard member.value.isString("assistant") else {
                    return nil
                }
                isAssistant = true
            case "timestamp": timestamp = try member.value.string()
            case "requestId": requestID = try member.value.string()
            case "effort": effort = try member.value.string()
            case "message": message = member.value
            default: continue
            }
        }
        guard isAssistant, var message = try message?.object() else {
            return nil
        }
        var messageID: String?
        var model: String?
        var usage: ClaudeLoggedUsage?
        while let member = try message.next() {
            switch member.key {
            case "id": messageID = try member.value.string()
            case "model": model = try member.value.string()
            case "usage": usage = try ClaudeLoggedUsage(member.value)
            default: continue
            }
        }
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
        var usage = try value.object()
        var input: UInt64?
        var cacheRead: UInt64?
        var cacheCreationTotal: UInt64?
        var cacheCreationSplit: JSONValue?
        var output: UInt64?
        var speed: String?
        var geo: String?
        var webSearchRequests: UInt64?
        while let member = try usage.next() {
            switch member.key {
            case "input_tokens": input = try member.value.integer()
            case "cache_read_input_tokens": cacheRead = try member.value.integer()
            case "cache_creation_input_tokens": cacheCreationTotal = try member.value.integer()
            case "cache_creation": cacheCreationSplit = member.value.nonNull
            case "output_tokens": output = try member.value.integer()
            case "speed": speed = try member.value.string()
            case "inference_geo": geo = try member.value.string()
            case "server_tool_use":
                webSearchRequests = try member.value.nonNull?.member("web_search_requests")?.integer()
            default: continue
            }
        }
        guard let input, let output,
            let tokens = ClaudeTokenUsage(
                input: input,
                cacheRead: cacheRead ?? 0,
                cacheCreation: try Self.cacheCreation(total: cacheCreationTotal ?? 0, split: cacheCreationSplit),
                output: output
            )
        else {
            throw MalformedUsageRecord()
        }
        self.tokens = tokens
        self.speed = speed
        self.geo = geo
        self.webSearchRequests = webSearchRequests ?? 0
    }

    private static func cacheCreation(total: UInt64, split: JSONValue?) throws -> ClaudeTokenUsage.CacheCreation {
        guard var split = try split?.object() else {
            return .aggregate(total)
        }
        var fiveMinute: UInt64?
        var oneHour: UInt64?
        while let member = try split.next() {
            switch member.key {
            case "ephemeral_5m_input_tokens": fiveMinute = try member.value.integer()
            case "ephemeral_1h_input_tokens": oneHour = try member.value.integer()
            default: continue
            }
        }
        let (sum, overflow) = (fiveMinute ?? 0).addingReportingOverflow(oneHour ?? 0)
        guard !overflow, sum == total else {
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
