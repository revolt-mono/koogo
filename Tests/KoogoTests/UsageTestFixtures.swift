import Foundation

@testable import Koogo

let usageTestTimestamp = Date(timeIntervalSince1970: 1_787_680_800)

func codexUsageEvent(
    id: Int = 0,
    model: String,
    effort: String? = nil,
    uncachedInput: Int64,
    cachedInput: Int64 = 0,
    cacheWriteInput: Int64 = 0,
    output: Int64 = 0,
    at eventDate: Date = usageTestTimestamp
) -> UsageEvent {
    let processedTokens = uncachedInput + cachedInput + cacheWriteInput + output
    return .codex(
        UsageEvent.Codex(
            threadID: "thread-\(id)",
            turnID: nil,
            ordinal: nil,
            details: UsageEvent.Details(
                timestamp: eventDate,
                model: model,
                reasoningEffort: effort
            ),
            tokens: UsageEvent.Codex.Tokens(
                input: uncachedInput + cachedInput + cacheWriteInput,
                cachedInput: cachedInput,
                cacheWrite: cacheWriteInput,
                output: output,
                reasoningOutput: 0,
                processed: processedTokens
            ),
            cumulativeTotal: processedTokens
        )
    )
}

func claudeUsageEvent(
    model: String,
    uncachedInput: Int64 = 0,
    cachedInput: Int64 = 0,
    cacheWrite5MinuteInput: Int64 = 0,
    cacheWrite1HourInput: Int64 = 0,
    output: Int64 = 0,
    speed: UsageEvent.Claude.Speed = .standard,
    inferenceGeo: String? = nil,
    webSearchRequests: Int64 = 0,
    at eventDate: Date = usageTestTimestamp
) -> UsageEvent {
    .claude(
        UsageEvent.Claude(
            messageID: "message",
            requestID: "request",
            details: UsageEvent.Details(
                timestamp: eventDate,
                model: model,
                reasoningEffort: nil
            ),
            tokens: UsageEvent.Claude.Tokens(
                input: uncachedInput,
                cacheRead: cachedInput,
                cacheCreation: .byDuration(
                    fiveMinute: cacheWrite5MinuteInput,
                    oneHour: cacheWrite1HourInput
                ),
                output: output
            ),
            speed: speed,
            inferenceGeo: inferenceGeo,
            webSearchRequests: webSearchRequests
        )
    )
}
