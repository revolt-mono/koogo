import Foundation

@testable import Koogo

let usageTestTimestamp = Date(timeIntervalSince1970: 1_787_680_800)

func codexUsageEvent(
    id: Int = 0,
    model: String,
    effort: String? = nil,
    uncachedInput: UInt64,
    cachedInput: UInt64 = 0,
    cacheWriteInput: UInt64 = 0,
    output: UInt64 = 0,
    at eventDate: Date = usageTestTimestamp
) -> UsageEvent {
    let tokens = codexTokenUsage(
        uncachedInput: uncachedInput,
        cachedInput: cachedInput,
        cacheWriteInput: cacheWriteInput,
        output: output
    )
    guard let quote = CodexUsagePricing.quote(model: model, tokens: tokens) else {
        preconditionFailure("unsupported codex model in test fixture")
    }
    return .codex(
        id: UsageEvent.CodexID(
            threadID: "thread-\(id)",
            turnID: nil,
            ordinal: nil,
            timestamp: eventDate,
            model: model,
            tokens: tokens,
            cumulativeTotal: tokens.processed
        ),
        usage: UsageRecord(
            timestamp: eventDate,
            processedTokens: tokens.processed,
            costUSD: quote.costUSD,
            modelTurn: UsageRecord.ModelTurn(model: quote.model, reasoningEffort: effort)
        )
    )
}

func codexTokenUsage(
    uncachedInput: UInt64,
    cachedInput: UInt64 = 0,
    cacheWriteInput: UInt64 = 0,
    output: UInt64 = 0
) -> CodexTokenUsage {
    guard
        let usage = CodexTokenUsage(
            input: uncachedInput + cachedInput + cacheWriteInput,
            cachedInput: cachedInput,
            cacheWrite: cacheWriteInput,
            output: output,
            reasoningOutput: 0,
            processed: uncachedInput + cachedInput + cacheWriteInput + output
        )
    else {
        preconditionFailure("invalid codex usage fixture")
    }
    return usage
}

func claudeUsageEvent(
    model: String,
    uncachedInput: UInt64 = 0,
    cachedInput: UInt64 = 0,
    cacheWrite5MinuteInput: UInt64 = 0,
    cacheWrite1HourInput: UInt64 = 0,
    output: UInt64 = 0,
    speed: ClaudeUsageSpeed = .standard,
    inferenceGeo: String? = nil,
    webSearchRequests: UInt64 = 0,
    at eventDate: Date = usageTestTimestamp
) -> UsageEvent {
    let usage = claudeBillableUsage(
        uncachedInput: uncachedInput,
        cachedInput: cachedInput,
        cacheWrite5MinuteInput: cacheWrite5MinuteInput,
        cacheWrite1HourInput: cacheWrite1HourInput,
        output: output,
        speed: speed,
        inferenceGeo: inferenceGeo,
        webSearchRequests: webSearchRequests
    )
    guard let quote = ClaudeUsagePricing.quote(model: model, usage: usage) else {
        preconditionFailure("unsupported claude model in test fixture")
    }
    return .claude(
        id: UsageEvent.ClaudeID(messageID: "message", requestID: "request"),
        usage: UsageRecord(
            timestamp: eventDate,
            processedTokens: usage.tokens.processed,
            costUSD: quote.costUSD,
            modelTurn: UsageRecord.ModelTurn(model: quote.model, reasoningEffort: nil)
        ),
        revision: UsageEvent.ClaudeRevision(
            outputTokens: usage.tokens.output,
            metadataCompleteness: usage.metadataCompleteness(reasoningEffort: nil),
            processedTokens: usage.tokens.processed,
            timestamp: eventDate
        )
    )
}

func claudeBillableUsage(
    uncachedInput: UInt64 = 0,
    cachedInput: UInt64 = 0,
    cacheWrite5MinuteInput: UInt64 = 0,
    cacheWrite1HourInput: UInt64 = 0,
    output: UInt64 = 0,
    speed: ClaudeUsageSpeed = .standard,
    inferenceGeo: String? = nil,
    webSearchRequests: UInt64 = 0
) -> ClaudeBillableUsage {
    guard
        let tokens = ClaudeTokenUsage(
            input: uncachedInput,
            cacheRead: cachedInput,
            cacheCreation: .byDuration(
                fiveMinute: cacheWrite5MinuteInput,
                oneHour: cacheWrite1HourInput
            ),
            output: output
        )
    else {
        preconditionFailure("invalid claude usage fixture")
    }
    return ClaudeBillableUsage(
        tokens: tokens,
        speed: speed,
        inferenceGeo: inferenceGeo,
        webSearchRequests: webSearchRequests
    )
}
