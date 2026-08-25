import Darwin
import Foundation

actor UsageService {
    private struct FileIdentity: Equatable {
        let device: UInt64
        let inode: UInt64
    }

    private struct FileMetadata {
        let identity: FileIdentity
        let size: UInt64
        let modificationDate: Date

        init?(_ url: URL) {
            var status = Darwin.stat()
            guard url.path.withCString({ Darwin.lstat($0, &status) }) == 0 else {
                return nil
            }
            self.init(status: status)
        }

        init?(fileDescriptor: Int32) {
            var status = Darwin.stat()
            guard Darwin.fstat(fileDescriptor, &status) == 0 else {
                return nil
            }
            self.init(status: status)
        }

        private init?(status: Darwin.stat) {
            guard status.st_size >= 0, status.st_mode & S_IFMT == S_IFREG else {
                return nil
            }
            identity = FileIdentity(
                device: UInt64(status.st_dev),
                inode: UInt64(status.st_ino)
            )
            size = UInt64(status.st_size)
            modificationDate = Date(
                timeIntervalSince1970: TimeInterval(status.st_mtimespec.tv_sec)
                    + TimeInterval(status.st_mtimespec.tv_nsec) / 1_000_000_000
            )
        }
    }

    private struct TrackedFile {
        var metadata: FileMetadata
        var parsedOffset: UInt64
        var parsedTail: Data
        var parser: UsageFileParserState
        var events: [UsageEvent.ID: UsageEvent]
    }

    private static let parsedTailSize = 64
    private static let readChunkSize = 1_048_576

    private let locations: UsageLogLocations
    private let calendar: Calendar
    private let snapshotBuilder = UsageSnapshotBuilder(priceCatalog: UsagePriceCatalog())
    private let decoder = JSONDecoder()
    private var trackedFiles: [String: TrackedFile] = [:]
    private var indexedFrom: Date?

    private(set) var snapshot: UsageSnapshot?

    init(
        locations: UsageLogLocations = .standard,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.locations = locations
        self.calendar = calendar
    }

    @discardableResult
    func refresh(at date: Date = Date()) -> UsageSnapshot {
        guard let intervals = UsagePeriodIntervals.containing(date, calendar: calendar) else {
            let empty = UsageSnapshot(
                generatedAt: date,
                codex: .zero,
                claude: .zero
            )
            snapshot = empty
            return empty
        }

        if let indexedFrom, intervals.earliestStart < indexedFrom {
            trackedFiles.removeAll(keepingCapacity: true)
        } else {
            trackedFiles = trackedFiles.mapValues { tracked in
                var tracked = tracked
                tracked.events = tracked.events.filter {
                    $0.value.details.timestamp >= intervals.earliestStart
                }
                return tracked
            }
        }
        indexedFrom = intervals.earliestStart

        scanLogs(since: intervals.earliestStart)

        let nextSnapshot = snapshotBuilder.build(
            events: canonicalEvents(),
            at: date,
            intervals: intervals
        )
        snapshot = nextSnapshot
        return nextSnapshot
    }

    private func scanLogs(since earliestStart: Date) {
        let files = [
            (locations.codexSessions, UsageProvider.codex),
            (locations.codexArchivedSessions, UsageProvider.codex),
            (locations.claudeProjects, UsageProvider.claude),
        ].flatMap { root, provider in
            jsonlFiles(in: root).map { ($0, provider) }
        }.sorted { $0.0.path < $1.0.path }
        var seenPaths = Set<String>()

        for (url, provider) in files {
            let path = url.path
            seenPaths.insert(path)

            guard let metadata = FileMetadata(url) else {
                continue
            }

            if var tracked = trackedFiles[path] {
                let wasReplaced = tracked.parser.provider != provider
                    || tracked.metadata.identity != metadata.identity
                    || metadata.size < tracked.metadata.size
                    || (
                        metadata.size == tracked.metadata.size
                            && metadata.modificationDate != tracked.metadata.modificationDate
                    )
                if wasReplaced {
                    if let reparsed = parseEntireFile(
                        url,
                        path: path,
                        provider: provider,
                        since: earliestStart
                    ) {
                        tracked = reparsed
                    }
                } else if metadata.size > tracked.metadata.size {
                    parseAppendedBytes(url, path: path, tracked: &tracked, since: earliestStart)
                }
                trackedFiles[path] = tracked
            } else {
                trackedFiles[path] = parseEntireFile(
                    url,
                    path: path,
                    provider: provider,
                    since: earliestStart
                )
            }
        }

        for path in Set(trackedFiles.keys).subtracting(seenPaths) {
            trackedFiles[path] = nil
        }
    }

    private func parseEntireFile(
        _ url: URL,
        path: String,
        provider: UsageProvider,
        since earliestStart: Date
    ) -> TrackedFile? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }
        guard let metadata = FileMetadata(fileDescriptor: handle.fileDescriptor) else {
            return nil
        }

        var tracked = TrackedFile(
            metadata: metadata,
            parsedOffset: 0,
            parsedTail: Data(),
            parser: UsageFileParserState(provider: provider),
            events: [:]
        )
        guard parseBytes(
            handle,
            from: 0,
            through: metadata.size,
            path: path,
            tracked: &tracked,
            since: earliestStart
        ) else {
            return nil
        }
        return tracked
    }

    private func parseAppendedBytes(
        _ url: URL,
        path: String,
        tracked: inout TrackedFile,
        since earliestStart: Date
    ) {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return
        }
        defer { try? handle.close() }

        guard let metadata = FileMetadata(fileDescriptor: handle.fileDescriptor) else {
            return
        }

        if
            tracked.metadata.identity != metadata.identity
                || metadata.size < tracked.metadata.size
                || !parsedTailMatches(handle, tracked: tracked)
        {
            if let reparsed = parseEntireFile(
                url,
                path: path,
                provider: tracked.parser.provider,
                since: earliestStart
            ) {
                tracked = reparsed
            }
            return
        }

        var candidate = tracked
        guard parseBytes(
            handle,
            from: tracked.parsedOffset,
            through: metadata.size,
            path: path,
            tracked: &candidate,
            since: earliestStart
        ) else {
            return
        }
        candidate.metadata = metadata
        tracked = candidate
    }

    private func parseBytes(
        _ handle: FileHandle,
        from offset: UInt64,
        through endOffset: UInt64,
        path: String,
        tracked: inout TrackedFile,
        since earliestStart: Date
    ) -> Bool {
        do {
            try handle.seek(toOffset: offset)
            var readOffset = offset
            var pending = Data()

            while readOffset < endOffset {
                let remaining = endOffset - readOffset
                let count = Int(min(remaining, UInt64(Self.readChunkSize)))
                guard
                    let chunk = try handle.read(upToCount: count),
                    !chunk.isEmpty
                else {
                    return false
                }
                readOffset += UInt64(chunk.count)
                pending.append(chunk)

                guard let lastNewline = pending.lastIndex(of: 0x0A) else {
                    continue
                }
                let completeCount = pending.distance(
                    from: pending.startIndex,
                    to: pending.index(after: lastNewline)
                )
                parseCompleteLines(
                    Data(pending.prefix(completeCount)),
                    path: path,
                    tracked: &tracked,
                    since: earliestStart
                )
                tracked.parsedOffset += UInt64(completeCount)
                pending = Data(pending.dropFirst(completeCount))
            }

            return true
        } catch {
            return false
        }
    }

    private func parseCompleteLines(
        _ data: Data,
        path: String,
        tracked: inout TrackedFile,
        since earliestStart: Date
    ) {
        for line in data.split(separator: 0x0A) {
            guard
                tracked.parser.mightContainUsage(line),
                let event = tracked.parser.parse(Data(line), source: path, decoder: decoder),
                event.details.timestamp >= earliestStart
            else {
                continue
            }
            insert(event, into: &tracked.events)
        }

        if data.count >= Self.parsedTailSize {
            tracked.parsedTail = Data(data.suffix(Self.parsedTailSize))
        } else {
            var parsedTail = tracked.parsedTail
            parsedTail.append(contentsOf: data)
            tracked.parsedTail = Data(parsedTail.suffix(Self.parsedTailSize))
        }
    }

    private func parsedTailMatches(_ handle: FileHandle, tracked: TrackedFile) -> Bool {
        guard !tracked.parsedTail.isEmpty else {
            return true
        }

        do {
            try handle.seek(
                toOffset: tracked.parsedOffset - UInt64(tracked.parsedTail.count)
            )
            var data = Data()

            while data.count < tracked.parsedTail.count {
                let count = tracked.parsedTail.count - data.count
                guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else {
                    return false
                }
                data.append(chunk)
            }
            return data == tracked.parsedTail
        } catch {
            return false
        }
    }

    private func insert(
        _ event: UsageEvent,
        into events: inout [UsageEvent.ID: UsageEvent]
    ) {
        guard let existing = events[event.id] else {
            events[event.id] = event
            return
        }
        if event.isPreferred(over: existing) {
            events[event.id] = event
        }
    }

    private func canonicalEvents() -> [UsageEvent] {
        var result: [UsageEvent.ID: UsageEvent] = [:]

        for (_, tracked) in trackedFiles.sorted(by: { $0.key < $1.key }) {
            for event in tracked.events.values {
                insert(event, into: &result)
            }
        }

        return Array(result.values)
    }

    private func jsonlFiles(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "jsonl" else {
                return nil
            }
            return url
        }
    }
}
