import Darwin
import Foundation
import Synchronization

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

/// One log file read incrementally: bytes appended since the last pass are
/// parsed in place, while a rotated or truncated file is re-read from scratch.
private struct TrackedUsageFile: Sendable {
    private static let parsedTailSize = 64

    let location: UsageLogLocation
    private var metadata: UsageFileMetadata
    private var parsedOffset: UInt64
    private var parsedTail: Data
    private var parser: any UsageLogParser
    var eventIndex: UsageEventIndex

    init?(_ location: UsageLogLocation, since historyStart: Date) {
        guard let handle = try? FileHandle(forReadingFrom: location.url) else {
            return nil
        }
        defer { try? handle.close() }
        guard let metadata = UsageFileMetadata(fileDescriptor: handle.fileDescriptor) else {
            return nil
        }

        self.location = location
        self.metadata = metadata
        parsedOffset = 0
        parsedTail = Data()
        parser = location.provider.makeLogParser()
        eventIndex = UsageEventIndex(since: historyStart)
        guard readBytes(handle, in: 0..<metadata.size) else {
            return nil
        }
    }

    mutating func refresh(observed metadata: UsageFileMetadata) {
        let wasReplaced =
            self.metadata.identity != metadata.identity
            || metadata.size < self.metadata.size
            || (metadata.size == self.metadata.size
                && metadata.modificationDate != self.metadata.modificationDate)
        if wasReplaced {
            reread()
        } else if metadata.size > self.metadata.size {
            readAppendedBytes()
        }
    }

    private mutating func reread() {
        if let replacement = Self(location, since: eventIndex.historyStart) {
            self = replacement
        }
    }

    private mutating func readAppendedBytes() {
        guard let handle = try? FileHandle(forReadingFrom: location.url) else {
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
            reread()
            return
        }

        var candidate = self
        guard candidate.readBytes(handle, in: parsedOffset..<metadata.size) else {
            return
        }
        candidate.metadata = metadata
        self = candidate
    }

    private mutating func readBytes(_ handle: FileHandle, in offsets: Range<UInt64>) -> Bool {
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
                        pending.append(chunk.prefix(completeChunkCount))
                        parseCompleteLines(pending, decoder: decoder)
                        parsedOffset += UInt64(pending.count)
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

    private mutating func parseCompleteLines(_ data: Data, decoder: JSONDecoder) {
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
                if let outcome = parser.parse(line, decoder: decoder) {
                    eventIndex.insert(outcome)
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

/// Every `.jsonl` file under the provider log roots, tracked across refreshes.
struct UsageLogIndex {
    private let roots: [UsageLogLocation]
    private var trackedFiles: [String: TrackedUsageFile] = [:]
    private var indexedFrom: Date?

    init(locations: UsageLocations.Logs) {
        roots = locations.roots
    }

    var logRoots: [UsageIngestionStats.LogRoot] {
        roots.map {
            UsageIngestionStats.LogRoot(
                provider: $0.provider,
                path: $0.url.path,
                exists: FileManager.default.fileExists(atPath: $0.url.path)
            )
        }
    }

    var trackedFileCounts: [UsageProvider: Int] {
        trackedFiles.values.reduce(into: [.codex: 0, .claude: 0, .piAgent: 0]) { counts, tracked in
            counts[tracked.location.provider, default: 0] += 1
        }
    }

    /// Brings every tracked file up to date and returns the events merged across them.
    mutating func refresh(since historyStart: Date) -> UsageEventIndex {
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

        var merged = UsageEventIndex(since: historyStart)
        for (_, tracked) in trackedFiles.sorted(by: { $0.key < $1.key }) {
            merged.merge(tracked.eventIndex)
        }
        return merged
    }

    private mutating func scanLogs(since historyStart: Date) {
        let files = roots.flatMap { root in
            Self.jsonlFiles(in: root.url).map { UsageLogLocation(provider: root.provider, url: $0) }
        }
        var seenPaths = Set<String>()
        var newFiles: [UsageLogLocation] = []

        for file in files {
            let path = file.url.path
            seenPaths.insert(path)
            guard let metadata = UsageFileMetadata(file.url) else {
                continue
            }
            if var tracked = trackedFiles[path] {
                tracked.refresh(observed: metadata)
                trackedFiles[path] = tracked
            } else {
                newFiles.append(file)
            }
        }

        for (path, tracked) in Self.load(newFiles, since: historyStart) {
            trackedFiles[path] = tracked
        }
        for path in Set(trackedFiles.keys).subtracting(seenPaths) {
            trackedFiles[path] = nil
        }
    }

    private static func load(
        _ files: [UsageLogLocation],
        since historyStart: Date
    ) -> [String: TrackedUsageFile] {
        let trackedFiles = Mutex<[String: TrackedUsageFile]>([:])
        // Keep refresh synchronous so actor state cannot interleave while workers build files.
        DispatchQueue.concurrentPerform(iterations: files.count) { index in
            let file = files[index]
            guard let tracked = TrackedUsageFile(file, since: historyStart) else {
                return
            }
            trackedFiles.withLock { $0[file.url.path] = tracked }
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
