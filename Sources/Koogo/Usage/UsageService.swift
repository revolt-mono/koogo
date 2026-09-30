import Foundation

struct UsageReport: Sendable, Encodable {
    let ingestion: UsageIngestionStats
    let snapshot: UsageSnapshot
}

actor UsageService {
    private struct LastRefresh {
        let intervals: UsagePeriodIntervals
        let providers: Set<Provider>
        let report: UsageReport
    }

    let locations: UsageLocations
    private let calendar: Calendar
    private var logIndex: UsageLogIndex
    private var lastRefresh: LastRefresh?

    init(
        locations: UsageLocations = .standard,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.locations = locations
        self.calendar = calendar
        logIndex = UsageLogIndex(locations: locations)
    }

    func refresh(
        at date: Date,
        providers: Set<Provider> = Set(Provider.allCases)
    ) -> UsageReport {
        let started = ContinuousClock.now
        let intervals = UsagePeriodIntervals(containing: date, calendar: calendar)
        let logsChanged = logIndex.refresh(since: intervals.historyStart, providers: providers)
        if !logsChanged, let lastRefresh, lastRefresh.intervals == intervals, lastRefresh.providers == providers {
            return lastRefresh.report
        }
        let (events, ingestion) = logIndex.collect()

        let files = ingestion.trackedFiles.values.reduce(0, +)
        let eventCount = ingestion.events.values.reduce(0, +)
        Telemetry.usage.info(
            """
            refresh files=\(files, privacy: .public) events=\(eventCount, privacy: .public) \
            duration=\(ContinuousClock.now - started, privacy: .public)
            """
        )
        let malformed = ingestion.malformedLines.filter { $0.value > 0 }
        if !malformed.isEmpty {
            let counts = malformed.map { "\($0.key.rawValue)=\($0.value)" }.sorted().joined(separator: ",")
            Telemetry.usage.warning("dropped malformed lines: \(counts, privacy: .public)")
        }
        if !ingestion.unpricedModels.isEmpty {
            let models = ingestion.unpricedModels.joined(separator: ",")
            Telemetry.usage.warning("dropped events without a price: \(models, privacy: .public)")
        }

        let report = UsageReport(
            ingestion: ingestion,
            snapshot: UsageSnapshotBuilder.build(events: events, providers: providers, intervals: intervals)
        )
        lastRefresh = LastRefresh(intervals: intervals, providers: providers, report: report)
        return report
    }
}
