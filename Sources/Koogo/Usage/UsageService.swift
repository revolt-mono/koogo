import Foundation

actor UsageService {
    private let calendar: Calendar
    private var logIndex: UsageLogIndex

    init(
        locations: UsageLogLocations = .standard,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.calendar = calendar
        logIndex = UsageLogIndex(locations: locations)
    }

    func refresh(at date: Date = Date()) -> UsageSnapshot {
        let intervals = UsagePeriodIntervals(containing: date, calendar: calendar)
        return UsageSnapshotBuilder.build(
            events: logIndex.events(since: intervals.month.previous.lowerBound),
            intervals: intervals,
            calendar: calendar
        )
    }
}
