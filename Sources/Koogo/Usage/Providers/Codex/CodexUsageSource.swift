import Foundation

/// Codex rollout logs: every `.jsonl` under the live and archived session roots.
struct CodexUsageSource: UsageLogSource {
    let homePath = ".codex"
    let logDirectories = ["sessions", "archived_sessions"]

    func openLog(at url: URL, since historyStart: Date) -> (any UsageLog)? {
        UsageLogFile(url, parser: CodexLogParser(), since: historyStart)
    }
}
