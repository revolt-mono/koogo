import Foundation

/// Grok Build sessions: each session directory under the sessions root is one log.
struct GrokUsageSource: UsageLogSource {
    let homePath = ".grok"
    let logDirectories = ["sessions"]

    func openLog(at url: URL, since historyStart: Date) -> (any UsageLog)? {
        GrokSessionLog(url, since: historyStart)
    }
}
