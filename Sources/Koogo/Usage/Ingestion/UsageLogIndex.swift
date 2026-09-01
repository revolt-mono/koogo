import Darwin
import Foundation
import Synchronization

private struct UsageLogSource: Sendable {
    let url: URL
    let parser: UsageFileParserState
}

/// How the last refresh went; the pipeline drops unparseable input silently,
/// so this is the only place ingestion health becomes observable.
struct UsageIngestionStats: Equatable, Sendable, Encodable {
    let trackedFiles: [UsageProvider: Int]
    let events: [UsageProvider: Int]
    /// Models with events inside the history window that were dropped
    /// because no pricing entry matched.
    let unpricedModels: [String]
}

private struct UsageFileIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
}

private struct UsageFileMetadata: Equatable, Sendable {
    let identity: UsageFileIdentity
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
        identity = UsageFileIdentity(
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

private struct TrackedUsageFile: Sendable {
    private static let parsedTailSize = 64

    private var metadata: UsageFileMetadata
    private var parsedOffset: UInt64
    private var parsedTail: Data
    private var parser: UsageFileParserState
    var eventIndex: UsageEventIndex

    var provider: UsageProvider { parser.provider }

    init?(source: UsageLogSource, since historyStart: Date) {
        guard let handle = try? FileHandle(forReadingFrom: source.url) else {
            return nil
        }
        defer { try? handle.close() }
        guard let metadata = UsageFileMetadata(fileDescriptor: handle.fileDescriptor) else {
            return nil
        }

        self.metadata = metadata
        parsedOffset = 0
        parsedTail = Data()
        parser = source.parser
        eventIndex = UsageEventIndex()
        guard readBytes(handle, in: 0..<metadata.size, since: historyStart) else {
            return nil
        }
    }

    mutating func refresh(
        from source: UsageLogSource,
        observed metadata: UsageFileMetadata,
        since historyStart: Date
    ) {
        let wasReplaced =
            self.metadata.identity != metadata.identity
            || metadata.size < self.metadata.size
            || (metadata.size == self.metadata.size
                && metadata.modificationDate != self.metadata.modificationDate)
        if wasReplaced {
            if let replacement = Self(source: source, since: historyStart) {
                self = replacement
            }
        } else if metadata.size > self.metadata.size {
            readAppendedBytes(from: source, since: historyStart)
        }
    }

    private mutating func readAppendedBytes(
        from source: UsageLogSource,
        since historyStart: Date
    ) {
        guard let handle = try? FileHandle(forReadingFrom: source.url) else {
            return
        }
        defer { try? handle.close() }
        guard let metadata = UsageFileMetadata(fileDescriptor: handle.fileDescriptor) else {
            return
        }

        guard self.metadata.identity == metadata.identity,
            metadata.size >= self.metadata.size,
            parsedTailMatches(handle)
        else {
            if let replacement = Self(source: source, since: historyStart) {
                self = replacement
            }
            return
        }

        var candidate = self
        guard
            candidate.readBytes(
                handle,
                in: parsedOffset..<metadata.size,
                since: historyStart
            )
        else {
            return
        }
        candidate.metadata = metadata
        self = candidate
    }

    private mutating func readBytes(
        _ handle: FileHandle,
        in offsets: Range<UInt64>,
        since historyStart: Date
    ) -> Bool {
        do {
            try handle.seek(toOffset: offsets.lowerBound)
            var readOffset = offsets.lowerBound
            var pending = Data()
            let decoder = JSONDecoder()

            while readOffset < offsets.upperBound {
                guard
                    try autoreleasepool(invoking: { () -> Bool in
                        let count = Int(min(offsets.upperBound - readOffset, 1_048_576))
                        guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else {
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
                        let completeData: Data
                        if pending.isEmpty {
                            completeData = Data(chunk.prefix(completeChunkCount))
                        } else {
                            pending.append(chunk.prefix(completeChunkCount))
                            completeData = pending
                        }
                        parseCompleteLines(
                            completeData,
                            since: historyStart,
                            decoder: decoder
                        )
                        parsedOffset += UInt64(completeData.count)
                        pending = Data(chunk.dropFirst(completeChunkCount))
                        return true
                    })
                else {
                    return false
                }
            }
            return true
        } catch {
            return false
        }
    }

    private mutating func parseCompleteLines(
        _ data: Data,
        since historyStart: Date,
        decoder: JSONDecoder
    ) {
        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return
            }
            var lineStart = 0

            while lineStart < bytes.count {
                let start = baseAddress.advanced(by: lineStart)
                guard let newline = memchr(start, Int32(0x0A), bytes.count - lineStart) else {
                    break
                }
                let lineCount = start.distance(to: newline)
                let line = UnsafeRawBufferPointer(start: start, count: lineCount)
                switch parser.parse(line, decoder: decoder) {
                case .event(let event)? where event.usage.timestamp >= historyStart:
                    eventIndex.insert(event)
                case .unpricedModel(let id, let timestamp)? where timestamp >= historyStart:
                    eventIndex.recordUnpricedModel(id, at: timestamp)
                default:
                    break
                }
                lineStart += lineCount + 1
            }
        }

        if data.count >= Self.parsedTailSize {
            parsedTail = Data(data.suffix(Self.parsedTailSize))
        } else {
            parsedTail.append(contentsOf: data)
            parsedTail = Data(parsedTail.suffix(Self.parsedTailSize))
        }
    }

    private func parsedTailMatches(_ handle: FileHandle) -> Bool {
        guard !parsedTail.isEmpty else {
            return true
        }

        do {
            try handle.seek(toOffset: parsedOffset - UInt64(parsedTail.count))
            var data = Data()
            while data.count < parsedTail.count {
                guard let chunk = try handle.read(upToCount: parsedTail.count - data.count),
                    !chunk.isEmpty
                else {
                    return false
                }
                data.append(chunk)
            }
            return data == parsedTail
        } catch {
            return false
        }
    }
}

struct UsageLogIndex {
    private let locations: UsageLocations.Logs
    private var trackedFiles: [String: TrackedUsageFile] = [:]
    private var indexedFrom: Date?

    init(locations: UsageLocations.Logs) {
        self.locations = locations
    }

    mutating func refresh(since historyStart: Date) {
        if let indexedFrom, historyStart < indexedFrom {
            trackedFiles.removeAll(keepingCapacity: true)
        } else if let indexedFrom, historyStart > indexedFrom {
            trackedFiles = trackedFiles.mapValues { tracked in
                var tracked = tracked
                tracked.eventIndex.discard(before: historyStart)
                return tracked
            }
        }
        scanLogs(since: historyStart)
        indexedFrom = historyStart
    }

    func mergedEvents() -> UsageEventIndex {
        var merged = UsageEventIndex()
        for (_, tracked) in trackedFiles.sorted(by: { $0.key < $1.key }) {
            merged.merge(tracked.eventIndex)
        }
        return merged
    }

    func stats(of merged: UsageEventIndex) -> UsageIngestionStats {
        var trackedFileCounts: [UsageProvider: Int] = [:]
        for tracked in trackedFiles.values {
            trackedFileCounts[tracked.provider, default: 0] += 1
        }
        var eventCounts: [UsageProvider: Int] = [:]
        for event in merged.values {
            eventCounts[event.provider, default: 0] += 1
        }
        return UsageIngestionStats(
            trackedFiles: trackedFileCounts,
            events: eventCounts,
            unpricedModels: merged.unpricedModelIDs.sorted()
        )
    }

    private mutating func scanLogs(since historyStart: Date) {
        let sources =
            (Self.jsonlFiles(in: locations.codex.sessions)
            + Self.jsonlFiles(in: locations.codex.archivedSessions)).map {
                UsageLogSource(url: $0, parser: .codex())
            }
            + Self.jsonlFiles(in: locations.claudeProjects).map {
                UsageLogSource(url: $0, parser: .claude)
            }
            + Self.jsonlFiles(in: locations.piAgent).map {
                UsageLogSource(url: $0, parser: .piAgent())
            }
        var seenPaths = Set<String>()
        var newSources: [UsageLogSource] = []

        for source in sources {
            let path = source.url.path
            seenPaths.insert(path)
            guard let metadata = UsageFileMetadata(source.url) else {
                continue
            }
            if var tracked = trackedFiles[path] {
                tracked.refresh(from: source, observed: metadata, since: historyStart)
                trackedFiles[path] = tracked
            } else {
                newSources.append(source)
            }
        }

        let loaded = Self.load(newSources, since: historyStart)
        for (path, tracked) in loaded {
            trackedFiles[path] = tracked
        }
        for path in Set(trackedFiles.keys).subtracting(seenPaths) {
            trackedFiles[path] = nil
        }
    }

    private static func load(
        _ sources: [UsageLogSource],
        since historyStart: Date
    ) -> [String: TrackedUsageFile] {
        let trackedFiles = Mutex<[String: TrackedUsageFile]>([:])
        // Keep refresh synchronous so actor state cannot interleave while workers build files.
        DispatchQueue.concurrentPerform(iterations: sources.count) { index in
            let source = sources[index]
            guard let tracked = TrackedUsageFile(source: source, since: historyStart) else {
                return
            }
            trackedFiles.withLock { $0[source.url.path] = tracked }
        }
        return trackedFiles.withLock { $0 }
    }

    private static func jsonlFiles(in root: URL) -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
        else {
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
