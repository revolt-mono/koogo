import Darwin
import Foundation
import Synchronization

struct LogStore: ~Copyable {
    private struct Entry: Sendable {
        let root: UsageLogRoot
        /// nil while the file was last written before the window or failed to open; both are rechecked without a
        /// directory event, since a resumed writer updates the modification time without one.
        var log: (any TrackedLog)?
    }

    private var entries: [String: Entry] = [:]
    private var logRoots: [UsageIngestionStats.LogRoot] = []
    private var windowStart = Date.distantPast
    private var watcher: LogDirectoryWatcher?

    mutating func sync(roots: [UsageLogRoot], since windowStart: Date) {
        let windowMoved = moveWindow(to: windowStart)
        let rootsChanged = updateRoots(roots)
        let reported = takeReportedChanges(for: roots)
        let changes = windowMoved || rootsChanged ? .everything : reported
        let walks = Self.walks(of: roots, for: changes)

        var unobserved = entries
        entries = Dictionary(minimumCapacity: unobserved.count)
        var newFiles: [(path: String, metadata: UsageFileMetadata, root: UsageLogRoot)] = []
        func observe(_ path: String, _ metadata: UsageFileMetadata, _ entry: consuming Entry) {
            if metadata.modificationDate < windowStart {
                entry.log = nil
            } else if entry.log == nil {
                newFiles.append((path, metadata, entry.root))
            } else {
                entry.log?.sync(observed: metadata)
            }
            entries[path] = entry
        }

        for (root, directory) in walks {
            Self.walk(root, from: directory) { path, metadata in
                observe(path, metadata, Entry(root: root, log: unobserved.removeValue(forKey: path)?.log))
            }
        }
        // fsevents reports an appended log only once its writer closes it, so files outside the walks are checked directly.
        if case .directories = changes {
            let walked = walks.map { $0.directory + "/" }
            // popping moves each log out, so syncing it appends in place instead of copying its events.
            while let (path, entry) = unobserved.popFirst() {
                if !walked.contains(where: path.hasPrefix), let metadata = UsageFileMetadata(path: path) {
                    observe(path, metadata, entry)
                }
            }
        }
        entries.merge(Self.open(newFiles, since: windowStart)) { $1 }
    }

    /// visits each request once, keeping the most complete copy across logs; equal copies keep the first path's.
    func collect(_ visit: (UsageEvent) -> Void) -> UsageIngestionStats {
        var trackedFiles = EnumMap<Provider, Int> { _ in 0 }
        var malformedLines = EnumMap<Provider, Int> { _ in 0 }
        var unpricedModels = Set<ModelID>()
        var indexes: [UsageEventIndex] = []
        for (_, entry) in entries.sorted(by: { $0.key < $1.key }) {
            guard let log = entry.log else {
                continue
            }
            trackedFiles[entry.root.provider] += 1
            malformedLines[entry.root.provider] += log.tally.malformedLines
            unpricedModels.formUnion(log.tally.unpricedModelIDs)
            indexes.append(log.events)
        }

        var events = EnumMap<Provider, Int> { _ in 0 }
        UsageEventIndex.forEachUnique(in: indexes) { event in
            events[event.provider] += 1
            visit(event)
        }
        return UsageIngestionStats(
            logRoots: logRoots,
            trackedFiles: trackedFiles,
            events: events,
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
