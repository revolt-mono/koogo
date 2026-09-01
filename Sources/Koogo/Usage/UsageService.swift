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

    func refresh(at date: Date) -> UsageSnapshot {
        let intervals = UsagePeriodIntervals(containing: date, calendar: calendar)
        logIndex.refresh(since: intervals.historyStart)
        return UsageSnapshotBuilder.build(
            events: logIndex.events(),
            intervals: intervals,
            calendar: calendar,
            piModels: PiModelCatalog(locations: piModelLocations)
        )
    }
}
