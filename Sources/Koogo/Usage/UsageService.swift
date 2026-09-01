import Foundation

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

    func refresh(at date: Date = Date()) -> UsageSnapshot {
        let intervals = UsagePeriodIntervals(endingAt: date)
        logIndex.refresh(since: intervals.last30Days.previous.lowerBound)
        return UsageSnapshotBuilder.build(
            events: logIndex.events(),
            intervals: intervals,
            calendar: calendar,
            piModels: PiModelCatalog(locations: piModelLocations)
        )
    }
}
