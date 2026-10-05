func claudeAssistant(model: String, usage: String, effort: String? = nil) -> String {
    let effortField = effort.map { "\"effort\":\"\($0)\"," } ?? ""
    return """
        {"type":"assistant","timestamp":"2026-08-25T12:00:00.000Z","requestId":"request",\(effortField)"message":{"id":"message","model":"\(model)","usage":{\(usage)}}}
        """
}

func claudeLog(output: Int) -> String {
    claudeAssistant(model: "claude-opus-5", usage: #""input_tokens":10,"output_tokens":\#(output)"#) + "\n"
}
