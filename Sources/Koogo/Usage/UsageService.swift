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
