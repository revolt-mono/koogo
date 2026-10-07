import Foundation

/// Pi logs its own prices, so the source only names models from the catalog under its home.
struct PiUsageSource: UsageSource {
    let logDirectories = ["sessions"]
    let logFormat = UsageLogFormat(match: .fileExtension(".jsonl")) { ParsedLog<PiUsageLogParser>($0, since: $1) }
    private var catalog = PiModelCatalog()

    mutating func refresh(home: URL) -> Bool {
        catalog.refresh(home: home)
    }

    func modelName(_ model: ModelID) -> String? {
        catalog.name(of: model)
    }
}
