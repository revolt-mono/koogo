import Foundation

struct GrokUsageSource: UsageLogSource {
    let homePath = ".grok"
    let logDirectories = ["sessions"]

    func openLog(at url: URL, since historyStart: Date) -> (any UsageLog)? {
        GrokSessionLog(url, since: historyStart)
    }
}
