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
    for provider in providers {
      sources[provider].refresh(home: provider.home(under: home))
    }

    var builder = UsageSnapshotBuilder(providers: providers, intervals: intervals)
    let ingestion = store.collect { builder.add($0) }
    log(ingestion, duration: ContinuousClock.now - started)
    return UsageReport(ingestion: ingestion, snapshot: builder.snapshot(sources: sources))
  }

  private let home: URL
  private let calendar: Calendar
  private var store = LogStore()
  private var sources = EnumMap<Provider, any UsageSource> { $0.usageSource }

  private func log(_ ingestion: UsageIngestionStats, duration: Duration) {
    let files = ingestion.trackedFiles.entries.reduce(0) { $0 + $1.value }
    let events = ingestion.events.entries.reduce(0) { $0 + $1.value }
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
