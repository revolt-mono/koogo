enum ClaudeLog {
  static func assistant(model: String, usage: String) -> String {
    """
    {"type":"assistant","timestamp":"\(UsageFixture.timestampText)","requestId":"request","message":{"id":"message","model":"\(model)","usage":{\(usage)}}}
    """
  }

  static func session(output: Int) -> String {
    assistant(model: "claude-opus-5", usage: #""input_tokens":10,"output_tokens":\#(output)"#) + "\n"
  }
}
