import Foundation

struct ClaudeUsageLogParser: UsageLogParser {
    func parse(_ line: UnsafeRawBufferPointer) throws -> UsageLineOutcome? {
        guard let reply = try ClaudeAssistantReply(line) else {
            return nil
        }
        let usage = reply.usage
        // claude logs synthetic replies such as api errors with zero usage and often no request id.
        guard usage.tokens.processed > 0 || usage.webSearchRequests > 0 else {
            return nil
        }
        guard let messageID = reply.messageID, !messageID.isEmpty, let requestID = reply.requestID, !requestID.isEmpty,
            let model = reply.model?.nonEmpty.map(ModelID.init(rawValue:)),
            let timestamp = reply.timestamp.flatMap(Date.init(iso8601:))
        else {
            throw MalformedUsageRecord()
        }
        guard let options = usage.options else {
            return .unpricedModel(model, timestamp: timestamp)
        }
        let billable = ClaudeBillableUsage(
            tokens: usage.tokens,
            options: options,
            webSearchRequests: usage.webSearchRequests
        )
        guard let quote = ClaudeUsagePricing.quote(model: model, usage: billable) else {
            return .unpricedModel(model, timestamp: timestamp)
        }

        return .event(
            UsageEvent(
                id: .claude(messageID: messageID, requestID: requestID),
                record: UsageRecord(
                    timestamp: timestamp,
                    processedTokens: usage.tokens.processed,
                    cost: quote.cost,
                    model: quote.model
                ),
                revision: usage.revision
            )
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
    /// surcharged reply options require support from the priced model.
    struct Options: OptionSet, Sendable {
        static let fastMode = Self(rawValue: 1 << 0)
        static let usInference = Self(rawValue: 1 << 1)

        let rawValue: UInt8
    }

    let tokens: ClaudeTokenUsage
    let options: Options
    let webSearchRequests: UInt64
}

/// the logged kind follows the message, so members are collected before any is decoded; the last duplicate wins.
private struct ClaudeAssistantReply {
    let timestamp: JSONText?
    let requestID: JSONText?
    let messageID: JSONText?
    let model: String?
    let usage: ClaudeLoggedUsage

    init?(_ line: UnsafeRawBufferPointer) throws {
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
        self.timestamp = try timestamp?.text()
        self.requestID = try requestID?.text()
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
        self.messageID = try messageID?.text()
        self.model = try model?.string()
        guard let usage = try usage.map(ClaudeLoggedUsage.init) else {
            return nil
        }
        self.usage = usage
    }
}

private struct ClaudeLoggedUsage {
    let tokens: ClaudeTokenUsage
    /// nil when the logged speed has no price.
    let options: ClaudeBillableUsage.Options?
    let revision: UsageEvent.Revision
    let webSearchRequests: UInt64

    init(_ value: JSONValue) throws {
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
        guard let input = try input?.uint64(), let output = try output?.uint64(),
            let tokens = ClaudeTokenUsage(
                input: input,
                cacheRead: try cacheRead?.uint64() ?? 0,
                cacheCreation: try Self.cacheCreation(
                    total: try cacheCreationTotal?.uint64() ?? 0,
                    split: cacheCreationSplit?.nonNull
                ),
                output: output
            )
        else {
            throw MalformedUsageRecord()
        }
        self.tokens = tokens
        webSearchRequests = try serverToolUse?.nonNull?.member("web_search_requests")?.uint64() ?? 0

        let loggedSpeed = try speed?.string()
        options = Self.options(speed: loggedSpeed, geo: try geo?.string())
        let explicitCacheDuration: UInt8 = if case .byDuration = tokens.cacheCreation { 1 } else { 0 }
        revision = UsageEvent.Revision(
            outputTokens: output,
            metadataCompleteness: (loggedSpeed == nil ? 0 : 1) + explicitCacheDuration
        )
    }

    private static func options(speed: String?, geo: String?) -> ClaudeBillableUsage.Options? {
        let region: ClaudeBillableUsage.Options = geo == "us" ? .usInference : []
        return switch speed {
        case nil, "standard": region
        case "fast": region.union(.fastMode)
        default: nil
        }
    }

    private static func cacheCreation(total: UInt64, split: JSONValue?) throws -> ClaudeTokenUsage.CacheCreation {
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
        let fiveMinuteTokens = try fiveMinute?.uint64() ?? 0
        let oneHourTokens = try oneHour?.uint64() ?? 0
        guard fiveMinuteTokens.checkedAdding(oneHourTokens) == total else {
            throw MalformedUsageRecord()
        }
        return .byDuration(fiveMinute: fiveMinuteTokens, oneHour: oneHourTokens)
    }
}

extension UsageEventID {
    static func claude(messageID: some Collection<UInt8>, requestID: some Collection<UInt8>) -> Self {
        Self(.claude) {
            $0.combine(text: messageID)
            $0.combine(text: requestID)
        }
    }
}
