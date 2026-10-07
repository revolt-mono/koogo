import Foundation
import XCTest

@testable import Koogo

let usageTestTimestamp = Date(timeIntervalSince1970: 1_787_680_800)

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
    let now = usageTestTimestamp

    override func setUpWithError() throws {
        workspace = try UsageTestWorkspace(root: try makeTemporaryDirectory())
    }

    func makePipeline() -> UsagePipeline {
        UsagePipeline(home: workspace.root, calendar: usageTestCalendar)
    }
}

func usageEvent(
    _ provider: Provider,
    id: Int = 0,
    model: String? = nil,
    effort: String? = nil,
    processedTokens: UInt64,
    costUSD: Decimal,
    at eventDate: Date = usageTestTimestamp
) -> UsageEvent {
    let record = UsageRecord(
        timestamp: eventDate,
        processedTokens: processedTokens,
        costUSD: costUSD,
        modelTurn: model.map { UsageRecord.ModelTurn(model: ModelID($0), reasoningEffort: effort) }
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

func grokMilliseconds(_ date: Date) -> UInt64 {
    UInt64(date.timeIntervalSince1970 * 1_000)
}

func usageSnapshot(
    events: [UsageEvent],
    providers: Set<Provider> = Set(Provider.allCases),
    intervals: UsagePeriodIntervals
) -> UsageSnapshot {
    var builder = UsageSnapshotBuilder(providers: providers, intervals: intervals)
    for event in events {
        builder.add(event)
    }
    return builder.snapshot(sources: EnumMap { $0.usageSource })
}
