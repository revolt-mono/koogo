import Foundation
import Testing

@testable import Koogo

enum UsageFixture {
  static let timestamp = Date(timeIntervalSince1970: 1_787_680_800)
  static let timestampText = timestamp.formatted(.iso8601)

  static let calendar: Calendar = {
    guard let utc = TimeZone(secondsFromGMT: 0) else {
      preconditionFailure("UTC time zone must exist")
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    return calendar
  }()
}

struct UsageTestWorkspace {
  init() throws {
    root = try scratch.makeTemporaryDirectory()
    for logRoot in Provider.allCases.flatMap({ $0.logRoots(under: root) }) {
      try FileManager.default.createDirectory(atPath: logRoot.path, withIntermediateDirectories: true)
    }
  }

  let root: URL

  var codexSessions: URL {
    logDirectory(.codex, "sessions")
  }

  var codexArchivedSessions: URL {
    logDirectory(.codex, "archived_sessions")
  }

  var claudeProjects: URL {
    logDirectory(.claude, "projects")
  }

  var piSessions: URL {
    logDirectory(.piAgent, "sessions")
  }

  var grokSessions: URL {
    logDirectory(.grok, "sessions")
  }

  func home(of provider: Provider) -> URL {
    provider.home(under: root)
  }

  func write(
    _ text: String,
    to url: URL,
    modificationDate: Date = UsageFixture.timestamp,
  ) throws {
    try write(Data(text.utf8), to: url, modificationDate: modificationDate)
  }

  func write(
    _ data: Data,
    to url: URL,
    modificationDate: Date = UsageFixture.timestamp,
  ) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true,
    )
    try data.write(to: url)
    try FileManager.default.setAttributes(
      [.modificationDate: modificationDate],
      ofItemAtPath: url.path,
    )
  }

  func openWriter(to url: URL) throws -> FileHandle {
    let writer = try FileHandle(forWritingTo: url)
    try writer.seekToEnd()
    return writer
  }

  func append(_ text: String, to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(text.utf8))
    try FileManager.default.setAttributes([.modificationDate: UsageFixture.timestamp], ofItemAtPath: url.path)
  }

  func makePipeline() -> UsagePipeline {
    UsagePipeline(home: root, calendar: UsageFixture.calendar)
  }

  func refresh(
    _ pipeline: UsagePipeline,
    until isCurrent: (UsageReport) -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation,
  ) async throws -> UsageReport {
    let deadline = ContinuousClock.now + .seconds(5)
    while true {
      let report = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases)
      if isCurrent(report) {
        return report
      }
      guard ContinuousClock.now < deadline else {
        Issue.record("the pipeline never reported the change", sourceLocation: sourceLocation)
        return report
      }
      try await Task.sleep(for: .milliseconds(10))
    }
  }

  private let scratch = Scratch()

  private func logDirectory(_ provider: Provider, _ directory: String) -> URL {
    home(of: provider).appending(path: directory, directoryHint: .isDirectory)
  }
}

extension UsageSnapshot {
  func todayTokens(_ provider: Provider) -> UInt64? {
    providers[provider]?.periods[.today].total.processedTokens
  }
}

extension UsageEvent {
  static func stub(
    _ provider: Provider,
    id: Int = 0,
    model: String? = nil,
    processedTokens: UInt64,
    costUSD: Decimal,
    at eventDate: Date = UsageFixture.timestamp,
  ) -> Self {
    let record = UsageRecord(
      timestamp: UsageTimestamp(eventDate),
      processedTokens: processedTokens,
      cost: Picodollars(usd: costUSD),
      model: model.map { ModelID(rawValue: $0) },
    )
    return UsageEvent(id: UsageEventID(provider) { $0.combine(id) }, record: record)
  }
}

extension Picodollars {
  init(usd: Decimal) {
    self.init(NSDecimalNumber(decimal: usd * 1_000_000_000_000).uint64Value)
  }
}

extension Date {
  var millisecondsSince1970: UInt64 {
    UInt64(timeIntervalSince1970 * 1_000)
  }
}

extension UsageSnapshot {
  init(
    events: [UsageEvent],
    providers: [Provider] = Provider.allCases,
    intervals: UsagePeriodIntervals = UsagePeriodIntervals(containing: UsageFixture.timestamp, calendar: UsageFixture.calendar),
  ) {
    var builder = UsageSnapshotBuilder(providers: providers, intervals: intervals)
    for event in events {
      builder.add(event)
    }
    self = builder.snapshot(modelNames: UsageModelNames())
  }
}

extension UsageEventIndex {
  var events: [UsageEvent] {
    var events = [UsageEvent]()
    Self.forEachUnique(in: [self]) { events.append($0) }
    return events
  }

  var count: Int {
    events.count
  }
}
