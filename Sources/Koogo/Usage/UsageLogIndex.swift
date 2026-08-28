import Darwin
import Foundation
import Synchronization

private struct UsageLogSource: Sendable {
    let url: URL
    let parser: UsageFileParserState
}

private struct UsageFileIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
}

private struct IndexedUsageEvents: Sendable {
    private var codex: [UsageEvent.CodexID: UsageRecord] = [:]
    private var claude: [UsageEvent.ClaudeID: (usage: UsageRecord, revision: UsageEvent.ClaudeRevision)] = [:]
    private var piAgent: [String: UsageRecord] = [:]

    var values: [UsageEvent] {
        var events: [UsageEvent] = []
        events.reserveCapacity(codex.count + claude.count + piAgent.count)
        events.append(
            contentsOf: codex.lazy.map { .codex(id: $0.key, usage: $0.value) }
        )
        events.append(
            contentsOf: claude.lazy.map {
                .claude(id: $0.key, usage: $0.value.usage, revision: $0.value.revision)
            }
        )
        events.append(
            contentsOf: piAgent.lazy.map { .piAgent(entryID: $0.key, usage: $0.value) }
        )
        return events
    }

    mutating func insert(_ event: UsageEvent) {
        switch event {
        case .codex(let id, let usage):
            guard codex[id] == nil else {
                return
            }
            codex[id] = usage
        case .claude(let id, let usage, let revision):
            if let existing = claude[id], !revision.isPreferred(over: existing.revision) {
                return
            }
            claude[id] = (usage, revision)
        case .piAgent(let entryID, let usage):
            guard piAgent[entryID] == nil else {
                return
            }
            piAgent[entryID] = usage
        }
    }

    mutating func merge(_ other: Self) {
        codex.merge(other.codex) { current, _ in current }
        claude.merge(other.claude) { current, candidate in
            candidate.revision.isPreferred(over: current.revision) ? candidate : current
        }
        piAgent.merge(other.piAgent) { current, _ in current }
    }

    mutating func discard(before historyStart: Date) {
        codex = codex.filter { $0.value.timestamp >= historyStart }
        claude = claude.filter { $0.value.usage.timestamp >= historyStart }
        piAgent = piAgent.filter { $0.value.timestamp >= historyStart }
    }
}

private struct UsageFileMetadata: Sendable {
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
    var events: IndexedUsageEvents

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
        events = IndexedUsageEvents()
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
                if let event = parser.parse(line, decoder: decoder),
                    event.usage.timestamp >= historyStart
                {
                    events.insert(event)
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

    mutating func events(since historyStart: Date) -> [UsageEvent] {
        if let indexedFrom, historyStart < indexedFrom {
            trackedFiles.removeAll(keepingCapacity: true)
        } else {
            trackedFiles = trackedFiles.mapValues { tracked in
                var tracked = tracked
                tracked.events.discard(before: historyStart)
                return tracked
            }
        }
        indexedFrom = historyStart
        scanLogs(since: historyStart)

        var events = IndexedUsageEvents()
        for (_, tracked) in trackedFiles.sorted(by: { $0.key < $1.key }) {
            events.merge(tracked.events)
        }
        return events.values
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

        for (path, tracked) in Self.load(newSources, since: historyStart) {
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
