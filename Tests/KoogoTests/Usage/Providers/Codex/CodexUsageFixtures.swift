import Foundation

/// `zstd -3` of `codexLog(input: 100, output: 20)`, as codex stores rollouts a week after their last write.
let codexCompressedLog = Data(
    base64Encoded: """
        KLUv/WQRAhUIAJIOKx9gZ9sGA5pfNpPQU22z2N8nhEHwCBb2NNEQjSLIMYABg6Zp8iiqt4+ZkMbastJ3zNPMHjMtTQ51HDMNdE7NuHa8clvH+lLvPlxvD31J\
        EcVMajqwfUgQlhy93yIQeryyXBgIhaIdcnRF1y7Ht8c0gXbbI7XHNMCgab6UvqSPvtgL0JdaJaHc8ap1SW0Zs/LR1SX6eIHMJGSiTGQYAYVTHLIwnDxH\
        d4tq1oX1CwIfAPlgCbhWAFiwBAsbQdTc6ALMAdWpmlzRI6vn5av2bMK0OUogZgBQDfypWZXKANkXOObvbCMSlmFrAwA2GVqL5jWMpWBCw4Dbs7VATkgu\
        45hwBlKDfXI=
        """
)!

func codexLog(
    input: Int,
    output: Int,
    turn: String = "turn",
    model: String = "gpt-5.6-sol",
    usageTimestamp: String = usageTestTimestampText
) -> String {
    let usage = codexUsage(input: input, output: output)
    return [
        codexMeta(),
        codexTurn(id: turn, model: model),
        codexTokenUsageRecord(usage, thread: usage, turn: turn, at: usageTimestamp),
        "",
    ].joined(separator: "\n")
}

func codexMeta(thread: String = "thread") -> String {
    """
    {"timestamp":"2026-08-25T11:00:00.000Z","type":"session_meta","payload":{"id":"\(thread)"}}
    """
}

func codexTurn(id: String = "turn", model: String = "gpt-5.6-sol") -> String {
    """
    {"timestamp":"2026-08-25T11:30:00.000Z","type":"turn_context","payload":{"turn_id":"\(id)","model":"\(model)","effort":"high"}}
    """
}

func codexUsage(
    input: Int,
    output: Int,
    cached: Int = 0,
    cacheWrite: Int? = nil,
    total: Int? = nil
) -> String {
    let cacheWriteField = cacheWrite.map { "\"cache_write_input_tokens\":\($0)," } ?? ""
    return """
        {"input_tokens":\(input),"cached_input_tokens":\(cached),\(cacheWriteField)"output_tokens":\(output),"reasoning_output_tokens":0,"total_tokens":\(total ?? input + output)}
        """
}

func codexTokenUsageRecord(
    _ usage: String,
    thread: String,
    turn: String = "turn",
    at timestamp: String = usageTestTimestampText
) -> String {
    """
    {"timestamp":"\(timestamp)","type":"token_usage_record","payload":{"thread_id":"thread","turn_id":"\(turn)","session_id":"thread","root_turn_id":"\(turn)","response_id":"resp_\(turn)","usage":\(usage),"turn_token_usage":\(usage),"thread_token_usage":\(thread)}}
    """
}
