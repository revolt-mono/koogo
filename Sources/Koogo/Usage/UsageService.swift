import Foundation

/// The single output of a usage pipeline run: what the UI renders plus how
/// ingestion went, so health is observable wherever the snapshot is.
struct UsageReport: Sendable, Encodable {
    let ingestion: UsageIngestionStats
    let snapshot: UsageSnapshot
}

actor UsageService {
    /// The inputs that shaped the last report; an unchanged set means the report can be reused.
    private struct LastRefresh {
        let intervals: UsagePeriodIntervals
        let providers: Set<UsageProvider>
        let piModels: PiModelCatalog
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
        logIndex = UsageLogIndex(roots: locations.logRoots)
    }

    func refresh(
        at date: Date,
        providers: Set<UsageProvider> = Set(UsageProvider.allCases)
    ) -> UsageReport {
        let started = ContinuousClock.now
        let intervals = UsagePeriodIntervals(containing: date, calendar: calendar)
        let changed = logIndex.refresh(since: intervals.historyStart, providers: providers)
        let piModels = providers.contains(.piAgent) ? PiModelCatalog(home: locations.home(of: .piAgent)) : .empty
        if !changed, let lastRefresh, lastRefresh.intervals == intervals, lastRefresh.providers == providers,
            lastRefresh.piModels == piModels
        {
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
        if !ingestion.unpricedModels.isEmpty {
            let models = ingestion.unpricedModels.joined(separator: ",")
            Telemetry.usage.warning("dropped events without a price: \(models, privacy: .public)")
        }

        let report = UsageReport(
            ingestion: ingestion,
            snapshot: UsageSnapshotBuilder.build(
                events: events,
                providers: providers,
                intervals: intervals,
                piModels: piModels
            )
        )
        lastRefresh = LastRefresh(intervals: intervals, providers: providers, piModels: piModels, report: report)
        return report
    }
}
