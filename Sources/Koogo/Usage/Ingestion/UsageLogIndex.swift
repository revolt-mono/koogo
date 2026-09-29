import Darwin
import Foundation
import Synchronization

/// An admitted log and its provider.
private struct TrackedUsageLog: Sendable {
    let provider: UsageProvider
    var log: any UsageLog
}

/// Every `.jsonl` file under the requested providers' log roots, tracked across refreshes by `fts` path.
/// Provider formats enter only through each provider's `UsageLogSource`.
struct UsageLogIndex {
    private let locations: UsageLocations
    private var sources: [UsageProvider: any UsageLogSource]
    private var logRoots: [UsageIngestionStats.LogRoot] = []
    private var trackedFiles: [String: TrackedUsageLog] = [:]
    private var indexedFrom = Date.distantPast

    init(locations: UsageLocations) {
        self.locations = locations
        sources = Dictionary(uniqueKeysWithValues: UsageProvider.allCases.map { ($0, $0.logSource) })
    }

    /// Events merged across every tracked file, with ingestion stats, as of the last `refresh`.
    func collect() -> (events: some Collection<UsageEvent>, stats: UsageIngestionStats) {
        var merged = UsageEventIndex(since: indexedFrom)
        merged.reserveCapacity(trackedFiles.values.reduce(0) { $0 + $1.log.events.count })
        for (_, tracked) in trackedFiles.sorted(by: { $0.key < $1.key }) {
            merged.merge(tracked.log.events)
        }
        let events = merged.values
        let stats = UsageIngestionStats(
            logRoots: logRoots,
            trackedFiles: Self.tally(trackedFiles.values.map { ($0.provider, 1) }),
            events: Self.tally(events.map { ($0.provider, 1) }),
            malformedLines: Self.tally(trackedFiles.values.map { ($0.provider, $0.log.malformedLines) }),
            unpricedModels: merged.unpricedModelIDs
        )
        return (events, stats)
    }

    /// Checks which roots exist, refreshes each requested provider's source and tracked files, drops
    /// all others, and reports whether the usage report may need rebuilding.
    mutating func refresh(since historyStart: Date, providers: Set<UsageProvider>) -> Bool {
        let roots = locations.logRoots
        let logRoots = roots.map {
            UsageIngestionStats.LogRoot(
                provider: $0.provider,
                path: $0.url.path,
                exists: FileManager.default.fileExists(atPath: $0.url.path)
            )
        }
        var changed = logRoots != self.logRoots
        self.logRoots = logRoots
        if historyStart < indexedFrom {
            trackedFiles.removeAll(keepingCapacity: true)
            changed = true
        } else if historyStart > indexedFrom {
            trackedFiles = trackedFiles.mapValues { tracked in
                var tracked = tracked
                tracked.log.discard(before: historyStart)
                return tracked
            }
            changed = true
        }
        for provider in providers {
            let home = locations.home(of: provider)
            guard sources[provider]?.refresh(home: home) == true else {
                continue
            }
            // Dropping the provider's logs makes the scan below reopen each with the refreshed source.
            trackedFiles = trackedFiles.filter { $0.value.provider != provider }
            changed = true
        }
        changed = scanLogs(roots.filter { providers.contains($0.provider) }, since: historyStart) || changed
        indexedFrom = historyStart
        return changed
    }

    private mutating func scanLogs(_ roots: [UsageLogLocation], since historyStart: Date) -> Bool {
        var seenPaths = Set<String>()
        var newFiles: [(path: String, provider: UsageProvider)] = []
        var changed = false

        for root in roots {
            Self.walkJSONL(in: root.url.path) { path, metadata in
                // A file's events all predate its last write, so a file last written
                // before the window cannot contribute and is not worth opening.
                guard metadata.modificationDate >= historyStart else {
                    return
                }
                seenPaths.insert(path)
                if let fileChanged = trackedFiles[path]?.log.refresh(observed: metadata) {
                    changed = fileChanged || changed
                } else {
                    newFiles.append((path, root.provider))
                }
            }
        }

        for (path, tracked) in Self.open(newFiles, with: sources, since: historyStart) {
            trackedFiles[path] = tracked
            changed = true
        }
        for path in trackedFiles.keys.filter({ !seenPaths.contains($0) }) {
            trackedFiles[path] = nil
            changed = true
        }
        return changed
    }

    private static func open(
        _ files: [(path: String, provider: UsageProvider)],
        with sources: [UsageProvider: any UsageLogSource],
        since historyStart: Date
    ) -> [String: TrackedUsageLog] {
        let trackedFiles = Mutex<[String: TrackedUsageLog]>([:])
        // Keep refresh synchronous so actor state cannot interleave while workers build files.
        // Each reader can grow its buffer to a whole log line; bound simultaneous readers.
        let nextFile = Atomic(0)
        DispatchQueue.concurrentPerform(iterations: min(files.count, 8)) { _ in
            // Workers claim files one at a time, so a few large logs cannot leave the rest idle.
            while case let index = nextFile.wrappingAdd(1, ordering: .relaxed).oldValue, index < files.count {
                let (path, provider) = files[index]
                let url = URL(filePath: path, directoryHint: .notDirectory)
                guard let log = sources[provider]?.openLog(at: url, since: historyStart) else {
                    continue
                }
                trackedFiles.withLock { $0[path] = TrackedUsageLog(provider: provider, log: log) }
            }
        }
        return trackedFiles.withLock { $0 }
    }

    private static func tally(_ counts: [(UsageProvider, Int)]) -> [UsageProvider: Int] {
        let zeros = Dictionary(uniqueKeysWithValues: UsageProvider.allCases.map { ($0, 0) })
        return counts.reduce(into: zeros) { totals, count in
            totals[count.0, default: 0] += count.1
        }
    }

    /// Walks `root` with `fts`, which hands back each entry's `stat` from the same
    /// directory read, so change detection costs no per-file syscalls or URL objects.
    /// A symlinked root is followed; symlinks below it are skipped.
    private static func walkJSONL(in root: String, _ body: (String, UsageFileMetadata) -> Void) {
        var paths: [UnsafeMutablePointer<CChar>?] = [strdup(root), nil]
        defer { free(paths[0]) }
        guard let stream = fts_open(&paths, FTS_PHYSICAL | FTS_COMFOLLOW | FTS_NOCHDIR, nil) else {
            return
        }
        defer { fts_close(stream) }
        while let entry = fts_read(stream) {
            let info = Int32(entry.pointee.fts_info)
            let status = entry.pointee.fts_statp.pointee
            let isHidden =
                entry.pointee.fts_name == CChar(UInt8(ascii: ".")) || status.st_flags & UInt32(UF_HIDDEN) != 0
            if entry.pointee.fts_level > 0, isHidden {
                if info == FTS_D {
                    fts_set(stream, entry, FTS_SKIP)
                }
                continue
            }
            guard info == FTS_F, let metadata = UsageFileMetadata(status: status) else {
                continue
            }
            let path = String(cString: entry.pointee.fts_path)
            if path.hasSuffix(".jsonl") {
                body(path, metadata)
            }
        }
    }
}
