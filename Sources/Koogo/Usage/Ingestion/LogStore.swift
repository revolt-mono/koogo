import Darwin
import Foundation
import Synchronization

struct LogStore {
    private struct Entry: Sendable {
        let provider: Provider
        var log: any TrackedLog
    }

    private var entries: [String: Entry] = [:]
    private var logRoots: [UsageIngestionStats.LogRoot] = []
    private var windowStart = Date.distantPast
    private var watcher: LogDirectoryWatcher?

    /// Brings the store in line with the files under the roots, walking only the directories FSEvents reported unless the roots or the window changed. Returns true when events may have changed.
    mutating func sync(roots: [UsageLogRoot], since windowStart: Date) -> Bool {
        let windowMoved = moveWindow(to: windowStart)
        let rootsChanged = updateRoots(roots)
        let reported = takeReportedChanges(for: roots)
        let changes = windowMoved || rootsChanged ? .everything : reported
        let walks = Self.walks(of: roots, for: changes)

        var changed = windowMoved || rootsChanged
        var seenPaths = Set<String>()
        var newFiles: [(path: String, metadata: UsageFileMetadata, root: UsageLogRoot)] = []
        for (root, directory) in walks {
            Self.walk(root, from: directory) { path, metadata in
                guard metadata.modificationDate >= windowStart else {
                    return
                }
                seenPaths.insert(path)
                if let fileChanged = entries[path]?.log.sync(observed: metadata) {
                    changed = fileChanged || changed
                } else {
                    newFiles.append((path, metadata, root))
                }
            }
        }

        for (path, entry) in Self.open(newFiles, since: windowStart) {
            entries[path] = entry
            changed = true
        }
        let gone = entries.keys.filter { path in
            guard !seenPaths.contains(path) else {
                return false
            }
            guard case .directories = changes else {
                return true
            }
            return walks.contains { path.hasPrefix($0.directory + "/") }
        }
        for path in gone {
            entries[path] = nil
            changed = true
        }
        return changed
    }

    /// Visits each request once and reports what every tracked log contributed. A request id logged in several files keeps its most complete copy.
    func collect(_ visit: (UsageEvent) -> Void) -> UsageIngestionStats {
        var trackedFiles = EnumMap<Provider, Int> { _ in 0 }
        var malformedLines = EnumMap<Provider, Int> { _ in 0 }
        var unpricedModels = Set<ModelID>()
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
                    shared.insert(event)
                } else {
                    countAndVisit(event)
                }
            }
        }
        shared.seal()
        shared.values.forEach(countAndVisit)
        return UsageIngestionStats(
            logRoots: logRoots,
            trackedFiles: trackedFiles,
            events: counts,
            malformedLines: malformedLines,
            unpricedModels: unpricedModels.sorted().map(\.rawValue)
        )
    }

    private mutating func moveWindow(to windowStart: Date) -> Bool {
        guard windowStart != self.windowStart else {
            return false
        }
        if windowStart < self.windowStart {
            entries.removeAll(keepingCapacity: true)
        } else {
            var index = entries.startIndex
            while index != entries.endIndex {
                entries.values[index].log.discard(before: windowStart)
                entries.formIndex(after: &index)
            }
        }
        self.windowStart = windowStart
        return true
    }

    private mutating func updateRoots(_ roots: [UsageLogRoot]) -> Bool {
        let logRoots = roots.map {
            UsageIngestionStats.LogRoot(
                provider: $0.provider,
                path: $0.path,
                exists: FileManager.default.fileExists(atPath: $0.path)
            )
        }
        defer { self.logRoots = logRoots }
        return logRoots != self.logRoots
    }

    /// What FSEvents reported since the last sync, or everything when no watcher covered that span on these roots. A replacement watcher starts before the walk, so a write during the walk reaches the next sync.
    private mutating func takeReportedChanges(for roots: [UsageLogRoot]) -> LogDirectoryWatcher.Changes {
        let paths = roots.map(\.path)
        guard let watcher, watcher.watches(paths) else {
            watcher = LogDirectoryWatcher(roots: paths)
            return .everything
        }
        return watcher.takeChanges()
    }

    /// Pairs each directory to walk with the root it lies under, skipping any directory inside another.
    private static func walks(
        of roots: [UsageLogRoot],
        for changes: LogDirectoryWatcher.Changes
    ) -> [(root: UsageLogRoot, directory: String)] {
        guard case .directories(let directories) = changes else {
            return roots.map { ($0, $0.path) }
        }
        var walks: [(root: UsageLogRoot, directory: String)] = []
        for directory in directories.sorted() where !walks.contains(where: { directory.hasPrefix($0.directory + "/") })
        {
            if let root = roots.first(where: { directory == $0.path || directory.hasPrefix($0.path + "/") }) {
                walks.append((root, directory))
            }
        }
        return walks
    }

    /// Visits the regular files under `directory`, which lies inside `root`, skipping hidden entries as a walk from the root would.
    private static func walk(_ root: UsageLogRoot, from directory: String, _ body: (String, UsageFileMetadata) -> Void)
    {
        let isRoot = directory == root.path
        guard isRoot || !isHidden(directory, under: root.path) else {
            return
        }
        var paths: [UnsafeMutablePointer<CChar>?] = [strdup(directory), nil]
        defer { free(paths[0]) }
        guard let stream = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR | (isRoot ? FTS_COMFOLLOW : 0), nil) else {
            return
        }
        defer { fts_close(stream) }
        while let entry = fts_read(stream) {
            let info = Int32(entry.pointee.fts_info)
            let status = entry.pointee.fts_statp.pointee
            if entry.pointee.fts_level > 0,
                isHidden(firstByte: UInt8(bitPattern: entry.pointee.fts_name), status: status)
            {
                if info == FTS_D {
                    fts_set(stream, entry, FTS_SKIP)
                }
                continue
            }
            guard info == FTS_F, let metadata = UsageFileMetadata(status: status) else {
                continue
            }
            let path = String(cString: entry.pointee.fts_path)
            if root.format.match.matches(path: path) {
                body(path, metadata)
            }
        }
    }

    /// Whether a directory below the root, or any directory between them, is hidden. A missing directory counts as hidden, since it holds nothing to walk.
    private static func isHidden(_ directory: String, under root: String) -> Bool {
        var path = root
        for component in directory.dropFirst(root.count + 1).split(separator: "/") {
            path += "/" + component
            var status = Darwin.stat()
            guard lstat(path, &status) == 0, !isHidden(firstByte: component.utf8.first ?? 0, status: status) else {
                return true
            }
        }
        return false
    }

    private static func isHidden(firstByte: UInt8, status: Darwin.stat) -> Bool {
        firstByte == UInt8(ascii: ".") || status.st_flags & UInt32(UF_HIDDEN) != 0
    }

    private static func open(
        _ files: [(path: String, metadata: UsageFileMetadata, root: UsageLogRoot)],
        since windowStart: Date
    ) -> [String: Entry] {
        let opened = Mutex<[String: Entry]>([:])
        let nextFile = Atomic(0)
        DispatchQueue.concurrentPerform(iterations: min(files.count, 4)) { _ in
            while case let index = nextFile.wrappingAdd(1, ordering: .relaxed).oldValue, index < files.count {
                let (path, metadata, root) = files[index]
                guard let log = root.format.open(path, metadata, windowStart) else {
                    continue
                }
                opened.withLock { $0[path] = Entry(provider: root.provider, log: log) }
            }
        }
        return opened.withLock { $0 }
    }
}
