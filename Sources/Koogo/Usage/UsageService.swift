import Foundation

actor UsageService {
    private let calendar: Calendar
    private let piModels: UsageLocations.PiModels
    private var logIndex: UsageLogIndex

    init(
        locations: UsageLocations = .standard,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.calendar = calendar
        piModels = locations.piModels
        logIndex = UsageLogIndex(locations: locations.logs)
    }

    func refresh(at date: Date = Date()) -> UsageSnapshot {
        let intervals = UsagePeriodIntervals(containing: date, calendar: calendar)
        return UsageSnapshotBuilder.build(
            events: logIndex.events(since: intervals.month.previous.lowerBound),
            intervals: intervals,
            calendar: calendar,
            piModels: PiModelCatalog(locations: piModels)
        )
    }
}
