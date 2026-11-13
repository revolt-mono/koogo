import XCTest

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
  init(root: URL) throws {
    self.root = root
    for provider in Provider.allCases {
      for directory in provider.usageSource.logDirectories {
        try FileManager.default.createDirectory(
          at: logDirectory(provider, directory),
          withIntermediateDirectories: true,
        )
      }
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

  /// an open writer appends without directory events, as a running agent does until it closes the log.
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

  private func logDirectory(_ provider: Provider, _ directory: String) -> URL {
    home(of: provider).appending(path: directory, directoryHint: .isDirectory)
  }
}

/// base class for suites that read provider logs from a temporary home.
class UsageWorkspaceTestCase: XCTestCase {
  // xctest builds the workspace in setUp, after init.
  // swiftlint:disable:next implicitly_unwrapped_optional
  private(set) var workspace: UsageTestWorkspace!

  override func setUpWithError() throws {
    workspace = try UsageTestWorkspace(root: makeTemporaryDirectory())
  }

  func makePipeline() -> UsagePipeline {
    UsagePipeline(home: workspace.root, calendar: UsageFixture.calendar)
  }

  /// polls until the report matches because filesystem events arrive after the write.
  func refresh(
    _ pipeline: UsagePipeline,
    until isCurrent: (UsageReport) -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line,
  ) async throws -> UsageReport {
    let deadline = ContinuousClock.now + .seconds(5)
    while true {
      let report = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases)
      if isCurrent(report) {
        return report
      }
      guard ContinuousClock.now < deadline else {
        XCTFail("the pipeline never reported the change", file: file, line: line)
        return report
      }
      try await Task.sleep(for: .milliseconds(10))
    }
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
      timestamp: eventDate,
      processedTokens: processedTokens,
      cost: Picodollars(usd: costUSD),
      model: model.map { ModelID(rawValue: $0) },
    )
    let eventID: UsageEventID =
      switch provider {
      case .codex: .codex(responseID: "response-\(id)".utf8)
      case .claude: .claude(messageID: "message-\(id)".utf8, requestID: "request-\(id)".utf8)
      case .piAgent: .piAgent(entryID: "entry-\(id)".utf8, timestamp: eventDate)
      case .grok: .grok(eventID: "event-\(id)".utf8, timestampMilliseconds: eventDate.millisecondsSince1970)
      }
    return UsageEvent(id: eventID, record: record)
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
    sources: EnumMap<Provider, any UsageSource> = EnumMap { $0.usageSource },
  ) {
    var builder = UsageSnapshotBuilder(providers: providers, intervals: intervals)
    for event in events {
      builder.add(event)
    }
    self = builder.snapshot(sources: sources)
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
