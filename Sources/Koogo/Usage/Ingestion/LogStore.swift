import Darwin
import Foundation
import Synchronization

/// Every log under the scanned roots, kept parsed between refreshes.
struct LogStore {
    private struct Entry: Sendable {
        let provider: Provider
        var log: any TrackedLog
    }

    private var entries: [String: Entry] = [:]
    private var logRoots: [UsageIngestionStats.LogRoot] = []
    private var windowStart = Date.distantPast

    /// Brings the store in line with the files under the roots. Returns true when events may have changed.
    mutating func sync(roots: [UsageLogRoot], since windowStart: Date) -> Bool {
        var changed = false
        if windowStart < self.windowStart {
            entries.removeAll(keepingCapacity: true)
            changed = true
        } else if windowStart > self.windowStart {
            var index = entries.startIndex
            while index != entries.endIndex {
                entries.values[index].log.discard(before: windowStart)
                entries.formIndex(after: &index)
            }
            changed = true
        }
        self.windowStart = windowStart

        let logRoots = roots.map {
            UsageIngestionStats.LogRoot(
                provider: $0.provider,
                path: $0.url.path,
                exists: FileManager.default.fileExists(atPath: $0.url.path)
            )
        }
        if logRoots != self.logRoots {
            self.logRoots = logRoots
            changed = true
        }

        var seenPaths = Set<String>()
        var newFiles: [(path: String, root: UsageLogRoot)] = []
        for root in roots {
            Self.walk(root) { path, metadata in
                guard metadata.modificationDate >= windowStart else {
                    return
                }
                seenPaths.insert(path)
                if let fileChanged = entries[path]?.log.sync(observed: metadata) {
                    changed = fileChanged || changed
                } else {
                    newFiles.append((path, root))
                }
            }
        }

        for (path, entry) in Self.open(newFiles, since: windowStart) {
            entries[path] = entry
            changed = true
        }
        for path in entries.keys.filter({ !seenPaths.contains($0) }) {
            entries[path] = nil
            changed = true
        }
        return changed
    }

    /// Visits each request once and reports what every tracked log contributed. A request id logged in
    /// several files keeps its most complete copy.
    func collect(_ visit: (UsageEvent) -> Void) -> UsageIngestionStats {
        var trackedFiles = EnumMap<Provider, Int> { _ in 0 }
        var malformedLines = EnumMap<Provider, Int> { _ in 0 }
        var unpricedModels = Set<String>()
        for entry in entries.values {
            trackedFiles[entry.provider] += 1
            malformedLines[entry.provider] += entry.log.tally.malformedLines
            unpricedModels.formUnion(entry.log.tally.unpricedModelIDs)
        }

        let logs = entries.sorted { $0.key < $1.key }.map(\.value.log)
        var seenHashes = Set<Int>(minimumCapacity: logs.reduce(0) { $0 + $1.events.count })
        var sharedHashes = Set<Int>()
        for log in logs {
            for id in log.events.keys where !seenHashes.insert(id.hashValue).inserted {
                sharedHashes.insert(id.hashValue)
            }
        }

        var counts = EnumMap<Provider, Int> { _ in 0 }
        func countAndVisit(_ event: UsageEvent) {
            counts[event.provider] += 1
            visit(event)
        }
        var shared = UsageEventIndex()
        for log in logs {
            for event in log.events.values {
                if sharedHashes.contains(event.id.hashValue) {
                    shared.insert(event, since: windowStart)
                } else {
                    countAndVisit(event)
                }
            }
        }
        shared.values.forEach(countAndVisit)
        return UsageIngestionStats(
            logRoots: logRoots,
            trackedFiles: trackedFiles,
            events: counts,
            malformedLines: malformedLines,
            unpricedModels: unpricedModels.sorted()
        )
    }

    /// Visits every matching regular file under the root, skipping hidden entries below it.
    private static func walk(_ root: UsageLogRoot, _ body: (String, UsageFileMetadata) -> Void) {
        var paths: [UnsafeMutablePointer<CChar>?] = [strdup(root.url.path), nil]
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
            if root.match.matches(path: path) {
                body(path, metadata)
            }
        }
    }

    private static func open(
        _ files: [(path: String, root: UsageLogRoot)],
        since windowStart: Date
    ) -> [String: Entry] {
        let opened = Mutex<[String: Entry]>([:])
        let nextFile = Atomic(0)
        DispatchQueue.concurrentPerform(iterations: min(files.count, 4)) { _ in
            while case let index = nextFile.wrappingAdd(1, ordering: .relaxed).oldValue, index < files.count {
                let (path, root) = files[index]
                let url = URL(filePath: path, directoryHint: .notDirectory)
                guard let log = root.open(url, windowStart) else {
                    continue
                }
                opened.withLock { $0[path] = Entry(provider: root.provider, log: log) }
            }
        }
        return opened.withLock { $0 }
    }
}
