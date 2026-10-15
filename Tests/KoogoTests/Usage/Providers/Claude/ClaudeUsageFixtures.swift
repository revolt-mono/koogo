func claudeAssistant(model: String, usage: String) -> String {
    """
    {"type":"assistant","timestamp":"\(usageTestTimestampText)","requestId":"request","message":{"id":"message","model":"\(model)","usage":{\(usage)}}}
    """
}

func claudeLog(output: Int) -> String {
    claudeAssistant(model: "claude-opus-5", usage: #""input_tokens":10,"output_tokens":\#(output)"#) + "\n"
}
