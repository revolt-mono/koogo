import Foundation

struct ClaudeUsageSource: UsageLogSource {
    let homePath = ".claude"
    let logDirectories = ["projects"]

    func openLog(at url: URL, since historyStart: Date) -> (any UsageLog)? {
        UsageLogFile(url, parser: ClaudeLogParser(), since: historyStart)
    }
}
