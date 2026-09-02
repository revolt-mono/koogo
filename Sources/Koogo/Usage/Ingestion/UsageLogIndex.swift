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

    init?(fileDescriptor: Int32) {
        var status = Darwin.stat()
        guard Darwin.fstat(fileDescriptor, &status) == 0 else {
            return nil
        }
        self.init(status: status)
    }

    init?(status: Darwin.stat) {
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

    /// Returns whether the file changed on disk since the last pass.
    mutating func refresh(observed metadata: UsageFileMetadata) -> Bool {
        let wasReplaced =
            self.metadata.identity != metadata.identity
            || metadata.size < self.metadata.size
            || (metadata.size == self.metadata.size
                && metadata.modificationDate != self.metadata.modificationDate)
        if wasReplaced {
            reread()
        } else if metadata.size > self.metadata.size {
            readAppendedBytes()
        } else {
            return false
        }
        return true
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

        // A failed read leaves the old size in place so the next pass retries from parsedOffset.
        if readBytes(handle, in: parsedOffset..<metadata.size) {
            self.metadata = metadata
        }
    }

    private mutating func readBytes(_ handle: FileHandle, in offsets: Range<UInt64>) -> Bool {
        let decoder = JSONDecoder()
        var readOffset = offsets.lowerBound
        var pending = Data()
        do {
            try handle.seek(toOffset: offsets.lowerBound)
            while readOffset < offsets.upperBound {
                let count = Int(min(offsets.upperBound - readOffset, 1_048_576))
                let didRead = try autoreleasepool {
                    guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else {
                        return false
                    }
                    readOffset += UInt64(chunk.count)
                    if pending.isEmpty {
                        pending = chunk
                    } else {
                        pending.append(chunk)
                    }
                    if let lastNewline = pending.withUnsafeBytes({ $0.lastIndex(of: 0x0A) }) {
                        let lines = pending.prefix(through: pending.startIndex + lastNewline)
                        parseCompleteLines(lines, decoder: decoder)
                        parsedOffset += UInt64(lines.count)
                        pending = Data(pending.dropFirst(lines.count))
                    }
                    return true
                }
                guard didRead else {
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

        parsedTail.append(data.suffix(Self.parsedTailSize))
        parsedTail = Data(parsedTail.suffix(Self.parsedTailSize))
    }

    private func parsedTailMatches(_ handle: FileHandle) -> Bool {
        guard !parsedTail.isEmpty else {
            return true
        }
        do {
            try handle.seek(toOffset: parsedOffset - UInt64(parsedTail.count))
            return try handle.read(upToCount: parsedTail.count) == parsedTail
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

    /// Events merged across every tracked file, as of the last `refresh`.
    var events: UsageEventIndex {
        var merged = UsageEventIndex(since: indexedFrom ?? .distantPast)
        for (_, tracked) in trackedFiles.sorted(by: { $0.key < $1.key }) {
            merged.merge(tracked.eventIndex)
        }
        return merged
    }

    /// Brings every tracked file up to date and reports whether `events` differ
    /// from the previous pass.
    mutating func refresh(since historyStart: Date) -> Bool {
        var changed = false
        if let indexedFrom, historyStart < indexedFrom {
            trackedFiles.removeAll(keepingCapacity: true)
            changed = true
        } else if let indexedFrom, historyStart > indexedFrom {
            trackedFiles = trackedFiles.mapValues { tracked in
                var tracked = tracked
                tracked.eventIndex.discard(before: historyStart)
                return tracked
            }
            changed = true
        }
        changed = scanLogs(since: historyStart) || changed
        indexedFrom = historyStart
        return changed
    }

    private mutating func scanLogs(since historyStart: Date) -> Bool {
        var seenPaths = Set<String>()
        var newFiles: [UsageLogLocation] = []
        var changed = false

        for root in roots {
            Self.walkJSONL(in: root.url.path) { path, metadata in
                // A file's events all predate its last write, so a file last written
                // before the window cannot contribute and is not worth opening.
                guard metadata.modificationDate >= historyStart else {
                    return
                }
                seenPaths.insert(path)
                if var tracked = trackedFiles[path] {
                    changed = tracked.refresh(observed: metadata) || changed
                    trackedFiles[path] = tracked
                } else {
                    newFiles.append(UsageLogLocation(provider: root.provider, url: URL(fileURLWithPath: path)))
                }
            }
        }

        for (path, tracked) in Self.load(newFiles, since: historyStart) {
            trackedFiles[path] = tracked
            changed = true
        }
        for path in trackedFiles.keys.filter({ !seenPaths.contains($0) }) {
            trackedFiles[path] = nil
            changed = true
        }
        return changed
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

    /// Walks `root` with `fts`, which hands back each entry's `stat` from the same
    /// directory read, so change detection costs no per-file syscalls or URL objects.
    private static func walkJSONL(in root: String, _ body: (String, UsageFileMetadata) -> Void) {
        var paths: [UnsafeMutablePointer<CChar>?] = [strdup(root), nil]
        defer { free(paths[0]) }
        guard let stream = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR, nil) else {
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
            if path.hasSuffix(".jsonl") {
                body(path, metadata)
            }
        }
    }
}
