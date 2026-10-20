import Darwin
import Foundation
import Synchronization

struct LogStore: ~Copyable {
    private struct Entry: Sendable {
        let root: UsageLogRoot
        /// nil while the file was last written before the window; a resumed writer updates the modification time without a directory event.
        var log: (any TrackedLog)?
    }

    private var entries: [String: Entry] = [:]
    private var logRoots: [UsageIngestionStats.LogRoot] = []
    private var windowStart = Date.distantPast
    private var watcher: LogDirectoryWatcher?

    /// syncs changed files under the roots; returns true when events or ingestion totals may have changed.
    mutating func sync(roots: [UsageLogRoot], since windowStart: Date) -> Bool {
        let windowMoved = moveWindow(to: windowStart)
        let rootsChanged = updateRoots(roots)
        let reported = takeReportedChanges(for: roots)
        let changes = windowMoved || rootsChanged ? .everything : reported
        let walks = Self.walks(of: roots, for: changes)

        var changed = windowMoved || rootsChanged
        var newFiles: [(path: String, metadata: UsageFileMetadata, root: UsageLogRoot)] = []
        func observe(_ path: String, _ metadata: UsageFileMetadata, under root: UsageLogRoot) {
            guard metadata.modificationDate >= windowStart else {
                changed = entries.updateValue(Entry(root: root, log: nil), forKey: path)?.log != nil || changed
                return
            }
            if let fileChanged = entries[path]?.log?.sync(observed: metadata) {
                changed = fileChanged || changed
            } else {
                newFiles.append((path, metadata, root))
            }
        }

        var seenPaths = Set<String>()
        for (root, directory) in walks {
            Self.walk(root, from: directory) { path, metadata in
                seenPaths.insert(path)
                observe(path, metadata, under: root)
            }
        }
        // fsevents reports an appended log only once its writer closes it, so files outside the walks are checked directly.
        for path in entries.keys.filter({ !seenPaths.contains($0) }) {
            if case .directories = changes, !walks.contains(where: { path.hasPrefix($0.directory + "/") }),
                let entry = entries[path], let metadata = UsageFileMetadata(path: path)
            {
                observe(path, metadata, under: entry.root)
            } else {
                changed = entries.removeValue(forKey: path)?.log != nil || changed
            }
        }
        for (path, entry) in Self.open(newFiles, since: windowStart) {
            entries[path] = entry
            changed = true
        }
        return changed
    }

    /// visits each request once, retaining the most complete copy across logs, and returns ingestion totals.
    func collect(_ visit: (UsageEvent) -> Void) -> UsageIngestionStats {
        var trackedFiles = EnumMap<Provider, Int> { _ in 0 }
        var malformedLines = EnumMap<Provider, Int> { _ in 0 }
        var unpricedModels = Set<ModelID>()
        for entry in entries.values {
            guard let log = entry.log else {
                continue
            }
            trackedFiles[entry.root.provider] += 1
            malformedLines[entry.root.provider] += log.tally.malformedLines
            unpricedModels.formUnion(log.tally.unpricedModelIDs)
        }

        let logs = entries.sorted { $0.key < $1.key }.compactMap(\.value.log)
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
        shared.update { batch in
            for log in logs {
                for event in log.events.values {
                    if sharedHashes.contains(event.id.hashValue) {
                        batch.insert(event)
                    } else {
                        countAndVisit(event)
                    }
                }
            }
        }
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
                entries.values[index].log?.discard(before: windowStart)
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

    private mutating func takeReportedChanges(for roots: [UsageLogRoot]) -> LogDirectoryWatcher.Changes {
        let paths = roots.map(\.path)
        guard let watcher, watcher.watches(paths) else {
            watcher = LogDirectoryWatcher(roots: paths)
            return .everything
        }
        return watcher.takeChanges()
    }

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

    private static func walk(_ root: UsageLogRoot, from directory: String, _ body: (String, UsageFileMetadata) -> Void)
    {
        let isRoot = directory == root.path
        guard isRoot || !isHiddenOrMissing(directory, under: root.path) else {
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

    private static func isHiddenOrMissing(_ directory: String, under root: String) -> Bool {
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
                opened.withLock { $0[path] = Entry(root: root, log: log) }
            }
        }
        return opened.withLock { $0 }
    }
}
