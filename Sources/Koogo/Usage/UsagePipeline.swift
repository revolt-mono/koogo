import Foundation

struct UsageReport: Sendable, Encodable {
    let ingestion: UsageIngestionStats
    let snapshot: UsageSnapshot
}

/// Log files to a usage report: discover, read, parse, dedup, aggregate, name.
actor UsagePipeline {
    private struct LastRun {
        let intervals: UsagePeriodIntervals
        let providers: [Provider]
        let report: UsageReport
    }

    private let home: URL
    private let calendar: Calendar
    private var store = LogStore()
    private var sources = EnumMap<Provider, any UsageSource> { $0.usageSource }
    private var lastRun: LastRun?

    init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.home = home
        self.calendar = calendar
    }

    /// Summarizes the requested providers whose tool is installed.
    func run(at date: Date, providers requested: [Provider]) -> UsageReport {
        let started = ContinuousClock.now
        let intervals = UsagePeriodIntervals(containing: date, calendar: calendar)
        let providers = Provider.allCases.filter {
            requested.contains($0) && FileManager.default.fileExists(atPath: $0.home(under: home).path)
        }
        let roots = providers.flatMap { sources[$0].logRoots(of: $0, home: home) }
        let logsChanged = store.sync(roots: roots, since: intervals.historyStart)
        var namesChanged = false
        for provider in providers {
            namesChanged = sources[provider].refresh(home: provider.home(under: home)) || namesChanged
        }
        if !logsChanged, !namesChanged, let lastRun, lastRun.intervals == intervals, lastRun.providers == providers {
            return lastRun.report
        }

        var builder = UsageSnapshotBuilder(providers: Set(providers), intervals: intervals)
        let ingestion = store.collect { builder.add($0) }
        log(ingestion, duration: ContinuousClock.now - started)

        let report = UsageReport(ingestion: ingestion, snapshot: builder.snapshot(sources: sources))
        lastRun = LastRun(intervals: intervals, providers: providers, report: report)
        return report
    }

    private func log(_ ingestion: UsageIngestionStats, duration: Duration) {
        let files = ingestion.trackedFiles.entries.reduce(0) { $0 + $1.value }
        let events = ingestion.events.entries.reduce(0) { $0 + $1.value }
        Telemetry.usage.info(
            """
            refresh files=\(files, privacy: .public) events=\(events, privacy: .public) \
            duration=\(duration, privacy: .public)
            """
        )
        let malformed = ingestion.malformedLines.entries.filter { $0.value > 0 }
        if !malformed.isEmpty {
            let counts = malformed.map { "\($0.key.rawValue)=\($0.value)" }.sorted().joined(separator: ",")
            Telemetry.usage.warning("dropped malformed lines: \(counts, privacy: .public)")
        }
        if !ingestion.unpricedModels.isEmpty {
            let models = ingestion.unpricedModels.joined(separator: ",")
            Telemetry.usage.warning("dropped events without a price: \(models, privacy: .public)")
        }
    }
}
