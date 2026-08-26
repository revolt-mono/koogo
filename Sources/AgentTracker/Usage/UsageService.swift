import Darwin
import Foundation
import Synchronization

actor UsageService {
    private struct LogFile: Sendable {
        let url: URL
        let provider: UsageProvider
    }

    private struct FileIdentity: Equatable, Sendable {
        let device: UInt64
        let inode: UInt64
    }

    private struct FileMetadata: Sendable {
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

    private struct TrackedFile: Sendable {
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
        let intervals = UsagePeriodIntervals.containing(date, calendar: calendar)

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
            intervals: intervals,
            calendar: calendar
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
            jsonlFiles(in: root).map { LogFile(url: $0, provider: provider) }
        }
        var seenPaths = Set<String>()
        var filesToParse: [LogFile] = []

        for file in files {
            let path = file.url.path
            seenPaths.insert(path)

            guard let metadata = FileMetadata(file.url) else {
                continue
            }
            if var tracked = trackedFiles[path] {
                let wasReplaced = tracked.parser.provider != file.provider
                    || tracked.metadata.identity != metadata.identity
                    || metadata.size < tracked.metadata.size
                    || (
                        metadata.size == tracked.metadata.size
                            && metadata.modificationDate != tracked.metadata.modificationDate
                    )
                if wasReplaced {
                    if let reparsed = Self.parseEntireFile(
                        file,
                        since: earliestStart
                    ) {
                        tracked = reparsed
                    }
                } else if metadata.size > tracked.metadata.size {
                    parseAppendedBytes(file, tracked: &tracked, since: earliestStart)
                }
                trackedFiles[path] = tracked
            } else {
                filesToParse.append(file)
            }
        }

        for (path, tracked) in Self.parseEntireFiles(filesToParse, since: earliestStart) {
            trackedFiles[path] = tracked
        }

        for path in Set(trackedFiles.keys).subtracting(seenPaths) {
            trackedFiles[path] = nil
        }
    }

    nonisolated private static func parseEntireFiles(
        _ files: [LogFile],
        since earliestStart: Date
    ) -> [String: TrackedFile] {
        let parsedFiles = Mutex<[String: TrackedFile]>([:])
        // Keep refresh synchronous so actor state cannot interleave while workers build files.
        DispatchQueue.concurrentPerform(iterations: files.count) { index in
            let file = files[index]
            guard let tracked = parseEntireFile(file, since: earliestStart) else {
                return
            }
            parsedFiles.withLock { $0[file.url.path] = tracked }
        }
        return parsedFiles.withLock { $0 }
    }

    nonisolated private static func parseEntireFile(
        _ file: LogFile,
        since earliestStart: Date
    ) -> TrackedFile? {
        guard let handle = try? FileHandle(forReadingFrom: file.url) else {
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
            parser: UsageFileParserState(provider: file.provider),
            events: [:]
        )
        guard parseBytes(
            handle,
            from: 0,
            through: metadata.size,
            path: file.url.path,
            tracked: &tracked,
            since: earliestStart
        ) else {
            return nil
        }
        return tracked
    }

    private func parseAppendedBytes(
        _ file: LogFile,
        tracked: inout TrackedFile,
        since earliestStart: Date
    ) {
        guard let handle = try? FileHandle(forReadingFrom: file.url) else {
            return
        }
        defer { try? handle.close() }

        guard let metadata = FileMetadata(fileDescriptor: handle.fileDescriptor) else {
            return
        }

        if
            tracked.metadata.identity != metadata.identity
                || metadata.size < tracked.metadata.size
                || !Self.parsedTailMatches(handle, tracked: tracked)
        {
            if let reparsed = Self.parseEntireFile(
                file,
                since: earliestStart
            ) {
                tracked = reparsed
            }
            return
        }

        var candidate = tracked
        guard Self.parseBytes(
            handle,
            from: tracked.parsedOffset,
            through: metadata.size,
            path: file.url.path,
            tracked: &candidate,
            since: earliestStart
        ) else {
            return
        }
        candidate.metadata = metadata
        tracked = candidate
    }

    nonisolated private static func parseBytes(
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
            let decoder = JSONDecoder()

            while readOffset < endOffset {
                guard try autoreleasepool(invoking: { () -> Bool in
                    let remaining = endOffset - readOffset
                    let count = Int(min(remaining, UInt64(Self.readChunkSize)))
                    guard
                        let chunk = try handle.read(upToCount: count),
                        !chunk.isEmpty
                    else {
                        return false
                    }
                    readOffset += UInt64(chunk.count)

                    guard let lastNewline = chunk.lastIndex(of: 0x0A) else {
                        pending.append(chunk)
                        return true
                    }
                    let completeChunkCount = chunk.distance(
                        from: chunk.startIndex,
                        to: chunk.index(after: lastNewline)
                    )
                    let pendingCount = pending.count
                    let completeData: Data
                    if pending.isEmpty {
                        completeData = Data(chunk.prefix(completeChunkCount))
                    } else {
                        pending.append(chunk.prefix(completeChunkCount))
                        completeData = pending
                    }
                    parseCompleteLines(
                        completeData,
                        path: path,
                        tracked: &tracked,
                        since: earliestStart,
                        decoder: decoder
                    )
                    tracked.parsedOffset += UInt64(pendingCount + completeChunkCount)
                    pending = Data(chunk.dropFirst(completeChunkCount))
                    return true
                }) else {
                    return false
                }
            }

            return true
        } catch {
            return false
        }
    }

    nonisolated private static func parseCompleteLines(
        _ data: Data,
        path: String,
        tracked: inout TrackedFile,
        since earliestStart: Date,
        decoder: JSONDecoder
    ) {
        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return
            }
            var lineStart = 0

            while lineStart < bytes.count {
                let start = baseAddress.advanced(by: lineStart)
                let remainingCount = bytes.count - lineStart
                guard let newline = memchr(start, Int32(0x0A), remainingCount) else {
                    break
                }
                let lineCount = start.distance(to: newline)
                let line = UnsafeRawBufferPointer(start: start, count: lineCount)

                if
                    let event = tracked.parser.parse(line, source: path, decoder: decoder),
                    event.details.timestamp >= earliestStart
                {
                    insert(event, into: &tracked.events)
                }
                lineStart += lineCount + 1
            }
        }

        if data.count >= Self.parsedTailSize {
            tracked.parsedTail = Data(data.suffix(Self.parsedTailSize))
        } else {
            var parsedTail = tracked.parsedTail
            parsedTail.append(contentsOf: data)
            tracked.parsedTail = Data(parsedTail.suffix(Self.parsedTailSize))
        }
    }

    nonisolated private static func parsedTailMatches(
        _ handle: FileHandle,
        tracked: TrackedFile
    ) -> Bool {
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

    nonisolated private static func insert(
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
                Self.insert(event, into: &result)
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
