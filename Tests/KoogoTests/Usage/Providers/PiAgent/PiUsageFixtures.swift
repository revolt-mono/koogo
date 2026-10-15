func piAssistant(id: String, parentID: String?, model: String, usage: String) -> String {
    let parent = parentID.map { "\"\($0)\"" } ?? "null"
    return """
        {"type":"message","id":"\(id)","parentId":\(parent),"timestamp":"\(usageTestTimestampText)","message":{"role":"assistant","provider":"provider","model":"\(model)","timestamp":\(Int(usageTestTimestamp.timeIntervalSince1970 * 1_000)),"usage":\(usage)}}
        """
}

func piUsage(
    input: Int,
    output: Int = 0,
    cacheRead: Int = 0,
    cacheWrite: Int = 0,
    cost: String
) -> String {
    """
    {"input":\(input),"output":\(output),"cacheRead":\(cacheRead),"cacheWrite":\(cacheWrite),"totalTokens":\(input + output + cacheRead + cacheWrite),"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"total":\(cost)}}
    """
}
