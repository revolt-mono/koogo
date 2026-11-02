import Foundation

/// `zstd -3` of `codexLog(input: 100, output: 20)`, as codex stores rollouts a week after their last write.
let codexCompressedLog = Data(
    base64Encoded: """
        KLUv/WQQAgUIAJIOKx9gZ9sGA5pfNpPQU22z2N8nhEHwCBb2NNEQjSLIMYABg6Zp8iiqt4+ZkMbastJ3zNPMHjMtTQ51HDMNdE7NuHa8clvH+lLvPlxvD31J\
        EcVMajqwfUgQlhy93yIQeryyXBgIhaIdcnRF1y7Ht8c0gXbbI7XHNMCgab6UvqSPvtgL0JdaJaHc8ap1SW0Zs/LR1SX6eIHMJGSiTGQYAYVTHLIwnDxHd4tq\
        1oX1CwIeAPlgCbZWAFiwBAobAdTc6ALMAdWpmlzRI2vn5an2LMK0ifkAVBh/alalMkD2BY75O9uIhGXY2gCATYbWonkNYymY0DDg9mwtkBOSyzgmnAF9RZJi
        """
)!

func codexLog(
    input: Int,
    output: Int,
    response: String = "response",
    model: String = "gpt-5.6-sol",
    usageTimestamp: String = usageTestTimestampText
) -> String {
    [
        codexMeta(),
        codexTurn(model: model),
        codexTokenUsageRecord(codexUsage(input: input, output: output), response: response, at: usageTimestamp),
        "",
    ].joined(separator: "\n")
}

func codexMeta() -> String {
    """
    {"timestamp":"2026-08-25T11:00:00.000Z","type":"session_meta","payload":{"id":"thread"}}
    """
}

func codexTurn(model: String = "gpt-5.6-sol") -> String {
    """
    {"timestamp":"2026-08-25T11:30:00.000Z","type":"turn_context","payload":{"turn_id":"turn","model":"\(model)","effort":"high"}}
    """
}

func codexUsage(input: Int, output: Int, cached: Int = 0, cacheWrite: Int? = nil) -> String {
    let cacheWriteField = cacheWrite.map { "\"cache_write_input_tokens\":\($0)," } ?? ""
    return """
        {"input_tokens":\(input),"cached_input_tokens":\(cached),\(cacheWriteField)"output_tokens":\(output),"reasoning_output_tokens":0,"total_tokens":\(input + output)}
        """
}

func codexTokenUsageRecord(
    _ usage: String,
    response: String = "response",
    at timestamp: String = usageTestTimestampText
) -> String {
    """
    {"timestamp":"\(timestamp)","type":"token_usage_record","payload":{"thread_id":"thread","turn_id":"turn","session_id":"thread","root_turn_id":"turn","response_id":"\(response)","usage":\(usage),"turn_token_usage":\(usage),"thread_token_usage":\(usage)}}
    """
}
