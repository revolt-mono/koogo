import Darwin
import Foundation
import Synchronization

private struct TrackedUsageLog: Sendable {
    let provider: Provider
    var log: any UsageLog
}

struct UsageLogIndex {
    private let locations: UsageLocations
    private var sources: [Provider: any UsageLogSource]
    private var logRoots: [UsageIngestionStats.LogRoot] = []
    private var trackedFiles: [String: TrackedUsageLog] = [:]
    private var indexedFrom = Date.distantPast

    init(locations: UsageLocations) {
        self.locations = locations
        sources = Dictionary(uniqueKeysWithValues: Provider.allCases.map { ($0, $0.logSource) })
    }

    func collect(_ visit: (UsageEvent) -> Void) -> UsageIngestionStats {
        let logs = trackedFiles.sorted { $0.key < $1.key }.map(\.value.log)
        var seenHashes = Set<Int>(minimumCapacity: logs.reduce(0) { $0 + $1.events.count })
        var sharedHashes = Set<Int>()
        for log in logs {
            for key in log.events.keys {
                let hash = key.hashValue
                if !seenHashes.insert(hash).inserted {
                    sharedHashes.insert(hash)
                }
            }
        }

        let providers = Provider.allCases
        var eventCounts = [Int](repeating: 0, count: providers.count)
        func countAndVisit(_ event: UsageEvent) {
            if let slot = providers.firstIndex(of: event.provider) {
                eventCounts[slot] += 1
            }
            visit(event)
        }
        var shared = UsageEventIndex(since: indexedFrom)
        for log in logs {
            for event in log.events.values {
                if sharedHashes.contains(event.key.hashValue) {
                    shared.insert(.event(event))
                } else {
                    countAndVisit(event)
                }
            }
        }
        shared.values.forEach(countAndVisit)

        return UsageIngestionStats(
            logRoots: logRoots,
            trackedFiles: Self.tally(trackedFiles.values.map { ($0.provider, 1) }),
            events: Dictionary(uniqueKeysWithValues: zip(providers, eventCounts)),
            malformedLines: Self.tally(trackedFiles.values.map { ($0.provider, $0.log.malformedLines) }),
            unpricedModels: Set(logs.flatMap(\.events.unpricedModelIDs)).sorted()
        )
    }

    mutating func refresh(since historyStart: Date, providers: Set<Provider>) -> Bool {
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
            trackedFiles = trackedFiles.filter { $0.value.provider != provider }
            changed = true
        }
        changed = scanLogs(roots.filter { providers.contains($0.provider) }, since: historyStart) || changed
        indexedFrom = historyStart
        return changed
    }

    private mutating func scanLogs(_ roots: [UsageLogLocation], since historyStart: Date) -> Bool {
        var seenPaths = Set<String>()
        var newFiles: [(path: String, provider: Provider)] = []
        var changed = false

        for root in roots {
            guard let logFileSuffix = sources[root.provider]?.logFileSuffix else {
                continue
            }
            Self.walkLogs(in: root.url.path, matching: logFileSuffix) { path, metadata in
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
        _ files: [(path: String, provider: Provider)],
        with sources: [Provider: any UsageLogSource],
        since historyStart: Date
    ) -> [String: TrackedUsageLog] {
        let trackedFiles = Mutex<[String: TrackedUsageLog]>([:])
        let nextFile = Atomic(0)
        DispatchQueue.concurrentPerform(iterations: min(files.count, 4)) { _ in
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

    private static func tally(_ counts: [(Provider, Int)]) -> [Provider: Int] {
        let zeros = Dictionary(uniqueKeysWithValues: Provider.allCases.map { ($0, 0) })
        return counts.reduce(into: zeros) { totals, count in
            totals[count.0, default: 0] += count.1
        }
    }

    private static func walkLogs(
        in root: String,
        matching logFileSuffix: String,
        _ body: (String, UsageFileMetadata) -> Void
    ) {
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
            if path.hasSuffix(logFileSuffix) {
                body(path, metadata)
            }
        }
    }
}
