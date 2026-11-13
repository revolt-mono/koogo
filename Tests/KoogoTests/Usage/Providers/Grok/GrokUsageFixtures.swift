import Foundation

struct GrokModelRow {
  var input = 1_000_000
  var cachedInput = 400_000
  var output = 100_000
}

enum GrokLog {
  static func turn(
    eventID: String,
    at date: Date = UsageFixture.timestamp,
    models: [String: GrokModelRow] = ["grok-4.6-build": GrokModelRow()],
  ) -> String {
    let milliseconds = date.millisecondsSince1970
    let totalTokens = models.values.lazy.map { $0.input + $0.output }.reduce(0, +)
    let modelUsage = models.map { model, row in
      """
      "\(model)":{"inputTokens":\(row.input),"cachedReadTokens":\(row.cachedInput),"outputTokens":\(row.output),\
      "modelCalls":1,"costUsdTicks":1}
      """
    }
    return """
      {"timestamp":1,"method":"_x.ai/session/update","params":{"sessionId":"session","update":{\
      "sessionUpdate":"turn_completed","prompt_id":"prompt","stop_reason":"end_turn","usage":{\
      "totalTokens":\(totalTokens),"costUsdTicks":1,"modelUsage":{\(modelUsage.joined(separator: ","))}}},\
      "_meta":{"eventId":"\(eventID)","agentTimestampMs":\(milliseconds)}}}
      """
  }
}
