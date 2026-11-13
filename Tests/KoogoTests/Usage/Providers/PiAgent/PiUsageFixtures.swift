import Foundation

enum PiLog {
  static func assistant(
    id: String,
    parentID: String?,
    model: String,
    usage: String,
    requestedAt date: Date = UsageFixture.timestamp,
  ) -> String {
    let parent = parentID.map { "\"\($0)\"" } ?? "null"
    return """
      {"type":"message","id":"\(id)","parentId":\(parent),"timestamp":"\(UsageFixture.timestampText)","message":{"role":"assistant","provider":"provider","model":"\(model)","timestamp":\(date.millisecondsSince1970),"usage":\(usage)}}
      """
  }

  static func usage(
    input: Int,
    output: Int = 0,
    cacheRead: Int = 0,
    cacheWrite: Int = 0,
    cost: String,
  ) -> String {
    """
    {"input":\(input),"output":\(output),"cacheRead":\(cacheRead),"cacheWrite":\(cacheWrite),"totalTokens":\(input + output + cacheRead + cacheWrite),"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"total":\(cost)}}
    """
  }
}
