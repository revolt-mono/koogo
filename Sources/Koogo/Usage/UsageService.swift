import Foundation

actor UsageService {
    private struct SnapshotCache {
        let logRevision: UsageLogIndex.Revision
        let intervals: UsagePeriodIntervals
        let piModels: PiModelCatalog
        let snapshot: UsageSnapshot
    }

    private let calendar: Calendar
    private let piModelLocations: UsageLocations.PiModels
    private var logIndex: UsageLogIndex
    private var cache: SnapshotCache?

    init(
        locations: UsageLocations = .standard,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.calendar = calendar
        piModelLocations = locations.piModels
        logIndex = UsageLogIndex(locations: locations.logs)
    }

    func refresh(at date: Date = Date()) -> UsageSnapshot {
        let intervals = UsagePeriodIntervals(containing: date, calendar: calendar)
        let piModels = PiModelCatalog(locations: piModelLocations)
        let logRevision = logIndex.refresh(since: intervals.month.previous.lowerBound)
        if let cache,
            cache.logRevision == logRevision,
            cache.intervals == intervals,
            cache.piModels == piModels
        {
            return cache.snapshot
        }
        let snapshot = UsageSnapshotBuilder.build(
            events: logIndex.events(),
            intervals: intervals,
            calendar: calendar,
            piModels: piModels
        )
        cache = SnapshotCache(
            logRevision: logRevision,
            intervals: intervals,
            piModels: piModels,
            snapshot: snapshot
        )
        return snapshot
    }
}
