import Foundation

/// pi logs prices directly; the source supplies catalog model names.
struct PiUsageSource: UsageSource {
  let logDirectories = ["sessions"]
  let logFormat = UsageLogFormat.jsonLines(PiUsageLogParser.self)

  mutating func refresh(home: URL) {
    catalog.refresh(home: home)
  }

  func modelName(_ model: ModelID) -> String? {
    catalog.name(of: model)
  }

  private var catalog = PiModelCatalog()
}
