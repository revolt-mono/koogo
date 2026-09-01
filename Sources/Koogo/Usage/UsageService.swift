import Foundation

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
        logIndex.refresh(since: intervals.historyStart)
        let merged = logIndex.mergedEvents()
        let ingestion = logIndex.stats(of: merged)

        let files = ingestion.trackedFiles.values.reduce(0, +)
        let events = ingestion.events.values.reduce(0, +)
        let duration = String(describing: ContinuousClock.now - started)
        Telemetry.usage.info(
            """
            refresh files=\(files, privacy: .public) events=\(events, privacy: .public) \
            duration=\(duration, privacy: .public)
            """
        )
        if !ingestion.unpricedModels.isEmpty {
            let models = ingestion.unpricedModels.joined(separator: ",")
            Telemetry.usage.warning("dropped events for unpriced models: \(models, privacy: .public)")
        }

        return UsageReport(
            ingestion: ingestion,
            snapshot: UsageSnapshotBuilder.build(
                events: merged.values,
                intervals: intervals,
                calendar: calendar,
                piModels: PiModelCatalog(locations: piModelLocations)
            )
        )
    }
}
