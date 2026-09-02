import Foundation

/// How the last refresh went; the pipeline drops unparseable input silently,
/// so this is the only place ingestion health becomes observable.
struct UsageIngestionStats: Equatable, Sendable, Encodable {
    struct LogRoot: Equatable, Sendable, Encodable {
        let provider: UsageProvider
        let path: String
        let exists: Bool
    }

    let logRoots: [LogRoot]
    let trackedFiles: [UsageProvider: Int]
    let events: [UsageProvider: Int]
    /// Models with events inside the history window that were dropped
    /// because no pricing entry matched.
    let unpricedModels: [String]
}

/// The single output of a usage pipeline run: what the UI renders plus how
/// ingestion went, so health is observable wherever the snapshot is.
struct UsageReport: Sendable, Encodable {
    let ingestion: UsageIngestionStats
    let snapshot: UsageSnapshot
}

actor UsageService {
    private let calendar: Calendar
    private let piModelLocations: UsageLocations.PiModels
    private var logIndex: UsageLogIndex
    private var lastReport: (intervals: UsagePeriodIntervals, piModels: PiModelCatalog, report: UsageReport)?

    init(
        locations: UsageLocations = .standard,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.calendar = calendar
        piModelLocations = locations.piModels
        logIndex = UsageLogIndex(locations: locations.logs)
    }

    func refresh(at date: Date) -> UsageReport {
        let started = ContinuousClock.now
        let intervals = UsagePeriodIntervals(containing: date, calendar: calendar)
        let changed = logIndex.refresh(since: intervals.historyStart)
        let piModels = PiModelCatalog(locations: piModelLocations)
        let logRoots = logIndex.logRoots
        if !changed, let lastReport, lastReport.intervals == intervals, lastReport.piModels == piModels,
            lastReport.report.ingestion.logRoots == logRoots
        {
            return lastReport.report
        }
        let events = logIndex.events
        let ingestion = UsageIngestionStats(
            logRoots: logRoots,
            trackedFiles: logIndex.trackedFileCounts,
            events: events.counts,
            unpricedModels: events.unpricedModelIDs
        )

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
            Telemetry.usage.warning("dropped events for unpriced models: \(models, privacy: .public)")
        }

        let report = UsageReport(
            ingestion: ingestion,
            snapshot: UsageSnapshotBuilder.build(
                events: events.values,
                intervals: intervals,
                calendar: calendar,
                piModels: piModels
            )
        )
        lastReport = (intervals, piModels, report)
        return report
    }
}
