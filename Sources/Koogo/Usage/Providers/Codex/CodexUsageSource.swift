import Foundation

struct CodexUsageSource: UsageLogSource {
    let homePath = ".codex"
    let logDirectories = ["sessions", "archived_sessions"]

    func openLog(at url: URL, since historyStart: Date) -> (any UsageLog)? {
        UsageLogFile(url, parser: CodexLogParser(), since: historyStart)
    }
}
