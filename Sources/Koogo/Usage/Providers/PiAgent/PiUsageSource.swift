import Foundation

struct PiUsageSource: UsageLogSource {
    let homePath = ".pi/agent"
    let logDirectories = ["sessions"]

    private var models = PiModelCatalog()

    mutating func refresh(home: URL) -> Bool {
        models.refresh(home: home)
    }

    func openLog(at url: URL, since historyStart: Date) -> (any UsageLog)? {
        UsageLogFile(url, parser: PiLogParser(models: models), since: historyStart)
    }
}
