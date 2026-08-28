import Foundation

struct UsageLocations: Sendable {
    struct Logs: Sendable {
        struct Codex: Sendable {
            let sessions: URL
            let archivedSessions: URL
        }

        let codex: Codex
        let claudeProjects: URL
        let piAgent: URL
    }

    struct PiModels: Sendable {
        let custom: URL
        let store: URL
    }

    let logs: Logs
    let piModels: PiModels

    static let standard: Self = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let piAgent = home.appending(path: ".pi/agent", directoryHint: .isDirectory)
        return Self(
            logs: Logs(
                codex: Logs.Codex(
                    sessions: home.appending(path: ".codex/sessions", directoryHint: .isDirectory),
                    archivedSessions: home.appending(
                        path: ".codex/archived_sessions",
                        directoryHint: .isDirectory
                    )
                ),
                claudeProjects: home.appending(
                    path: ".claude/projects",
                    directoryHint: .isDirectory
                ),
                piAgent: piAgent.appending(path: "sessions", directoryHint: .isDirectory)
            ),
            piModels: PiModels(
                custom: piAgent.appending(path: "models.json", directoryHint: .notDirectory),
                store: piAgent.appending(path: "models-store.json", directoryHint: .notDirectory)
            )
        )
    }()
}

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
