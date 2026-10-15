import Foundation
import XCTest

@testable import Koogo

let usageTestTimestamp = Date(timeIntervalSince1970: 1_787_680_800)
let usageTestTimestampText = usageTestTimestamp.formatted(.iso8601)

let usageTestCalendar: Calendar = {
    guard let utc = TimeZone(secondsFromGMT: 0) else {
        preconditionFailure("UTC time zone must exist")
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    calendar.firstWeekday = 2
    return calendar
}()

struct UsageTestWorkspace {
    let root: URL

    var codexSessions: URL { logDirectory(.codex, "sessions") }
    var codexArchivedSessions: URL { logDirectory(.codex, "archived_sessions") }
    var claudeProjects: URL { logDirectory(.claude, "projects") }
    var piSessions: URL { logDirectory(.piAgent, "sessions") }
    var grokSessions: URL { logDirectory(.grok, "sessions") }

    init(root: URL) throws {
        self.root = root
        for provider in Provider.allCases {
            for directory in provider.usageSource.logDirectories {
                try FileManager.default.createDirectory(
                    at: logDirectory(provider, directory),
                    withIntermediateDirectories: true
                )
            }
        }
    }

    func home(of provider: Provider) -> URL {
        provider.home(under: root)
    }

    private func logDirectory(_ provider: Provider, _ directory: String) -> URL {
        home(of: provider).appending(path: directory, directoryHint: .isDirectory)
    }

    func write(
        _ text: String,
        to url: URL,
        modificationDate: Date = usageTestTimestamp
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: modificationDate],
            ofItemAtPath: url.path
        )
    }

    func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try FileManager.default.setAttributes([.modificationDate: usageTestTimestamp], ofItemAtPath: url.path)
    }
}

class UsageWorkspaceTestCase: XCTestCase {
    private(set) var workspace: UsageTestWorkspace!

    override func setUpWithError() throws {
        workspace = try UsageTestWorkspace(root: makeTemporaryDirectory())
    }

    func makePipeline() -> UsagePipeline {
        UsagePipeline(home: workspace.root, calendar: usageTestCalendar)
    }

    /// Refreshes until the report shows a change. FSEvents tells the pipeline about a write some milliseconds after it lands.
    func refresh(
        _ pipeline: UsagePipeline,
        until isCurrent: (UsageReport) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> UsageReport {
        let deadline = ContinuousClock.now + .seconds(5)
        while true {
            let report = await pipeline.run(at: usageTestTimestamp, providers: Provider.allCases)
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

func usageEvent(
    _ provider: Provider,
    id: Int = 0,
    model: String? = nil,
    processedTokens: UInt64,
    costUSD: Decimal,
    at eventDate: Date = usageTestTimestamp
) -> UsageEvent {
    let record = UsageRecord(
        timestamp: eventDate,
        processedTokens: processedTokens,
        cost: picodollars(costUSD),
        model: model.map { ModelID($0) }
    )
    let eventID: UsageEventID =
        switch provider {
        case .codex: .codex(turnID: "turn-\(id)", cumulativeTotal: processedTokens)
        case .claude: .claude(messageID: "message-\(id)", requestID: "request-\(id)")
        case .piAgent: .piAgent(entryID: "entry-\(id)")
        case .grok: .grok(eventID: "event-\(id)", timestampMilliseconds: grokMilliseconds(eventDate))
        }
    return UsageEvent(id: eventID, record: record)
}

func picodollars(_ usd: Decimal) -> Picodollars {
    Picodollars(NSDecimalNumber(decimal: usd * 1_000_000_000_000).uint64Value)
}

func grokMilliseconds(_ date: Date) -> UInt64 {
    UInt64(date.timeIntervalSince1970 * 1_000)
}

func usageSnapshot(
    events: [UsageEvent],
    providers: Set<Provider> = Set(Provider.allCases),
    intervals: UsagePeriodIntervals,
    sources: EnumMap<Provider, any UsageSource> = EnumMap { $0.usageSource }
) -> UsageSnapshot {
    var builder = UsageSnapshotBuilder(providers: providers, intervals: intervals)
    for event in events {
        builder.add(event)
    }
    return builder.snapshot(sources: sources)
}
