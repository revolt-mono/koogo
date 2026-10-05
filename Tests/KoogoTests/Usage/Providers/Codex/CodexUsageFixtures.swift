func codexLog(
    input: Int,
    output: Int,
    thread: String = "thread",
    model: String = "gpt-5.6-sol",
    usageTimestamp: String = "2026-08-25T12:00:00.000Z"
) -> String {
    let usage = codexUsage(input: input, output: output)
    return [
        codexMeta(thread: thread),
        codexTurn(model: model),
        codexTokenCount(last: usage, total: usage, at: usageTimestamp),
        "",
    ].joined(separator: "\n")
}

func codexMeta(thread: String = "thread") -> String {
    """
    {"timestamp":"2026-08-25T11:00:00.000Z","type":"session_meta","payload":{"id":"\(thread)"}}
    """
}

func codexTurn(id: String = "turn", model: String = "gpt-5.6-sol", effort: String = "high") -> String {
    """
    {"timestamp":"2026-08-25T11:30:00.000Z","type":"turn_context","payload":{"turn_id":"\(id)","model":"\(model)","effort":"\(effort)"}}
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

func codexTokenCount(last: String, total: String, at timestamp: String = "2026-08-25T12:00:00.000Z") -> String {
    """
    {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":\(last),"total_token_usage":\(total),"model_context_window":1000}}}
    """
}
