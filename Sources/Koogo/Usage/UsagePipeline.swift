import Foundation
import os

struct UsageReport: Sendable, Encodable {
  let ingestion: UsageIngestionStats
  let snapshot: UsageSnapshot
}

actor UsagePipeline {
  init(
    home: URL = FileManager.default.homeDirectoryForCurrentUser,
    calendar: Calendar = .autoupdatingCurrent,
  ) {
    self.home = home
    self.calendar = calendar
  }

  func run(at date: Date, providers requested: [Provider]) -> UsageReport {
    let started = ContinuousClock.now
    let intervals = UsagePeriodIntervals(containing: date, calendar: calendar)
    let providers = Provider.allCases.filter {
      requested.contains($0) && FileManager.default.fileExists(atPath: $0.home(under: home).path)
    }
    store.sync(roots: providers.flatMap { $0.logRoots(under: home) }, since: intervals.last30Days.lowerBound)
    modelNames.refresh(providers: providers, under: home)

    var builder = UsageSnapshotBuilder(providers: providers, intervals: intervals)
    let ingestion = store.collect { builder.add($0) }
    log(ingestion, duration: ContinuousClock.now - started)
    return UsageReport(ingestion: ingestion, snapshot: builder.snapshot(modelNames: modelNames))
  }

  private let home: URL
  private let calendar: Calendar
  private var store = LogStore()
  private var modelNames = UsageModelNames()

  private func log(_ ingestion: UsageIngestionStats, duration: Duration) {
    let files = ingestion.trackedFiles.values.reduce(0, +)
    let events = ingestion.events.values.reduce(0, +)
    Logger.usage.info(
      """
      refresh files=\(files, privacy: .public) events=\(events, privacy: .public) \
      duration=\(duration, privacy: .public)
      """
    )
    let malformed = ingestion.malformedLines.entries.filter { $0.value > 0 }
    if !malformed.isEmpty {
      let counts = malformed.map { "\($0.key.rawValue)=\($0.value)" }.sorted().joined(separator: ",")
      Logger.usage.warning("dropped malformed lines: \(counts, privacy: .public)")
    }
    if !ingestion.unpricedModels.isEmpty {
      let models = ingestion.unpricedModels.joined(separator: ",")
      Logger.usage.warning("dropped events without a price: \(models, privacy: .public)")
    }
  }
}
