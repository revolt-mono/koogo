import Darwin
import Foundation
import Synchronization
import System

private struct UsageFileIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
}

private struct UsageFileMetadata: Sendable {
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
/// The walk is provider-agnostic; per-file provider rules (admission and the parser switch) live only here.
private struct TrackedUsageFile: Sendable {
    private static let parsedTailSize = 64
    private static let readSize = 1 << 20

    let location: UsageLogLocation
    private var metadata: UsageFileMetadata
    private var parsedOffset: UInt64
    private var parsedTail: Data
    private var parser: any UsageLogParser
    var eventIndex: UsageEventIndex
    private(set) var decodedLines = 0
    private(set) var malformedLines = 0

    /// Starts tracking a file seen for the first time. A Grok log counts only once it has a top-level
    /// session summary; a rejected file is offered again on the next scan, and a reread never re-checks.
    static func admit(_ location: UsageLogLocation, since historyStart: Date) -> Self? {
        if location.provider == .grok, !GrokLogParser.isUsageLog(location.url) {
            return nil
        }
        return Self(location, since: historyStart)
    }

    init?(_ location: UsageLogLocation, since historyStart: Date) {
        guard let file = try? FileDescriptor.open(FilePath(location.url.path), .readOnly) else {
            return nil
        }
        defer { try? file.close() }
        guard let metadata = UsageFileMetadata(fileDescriptor: file.rawValue) else {
            return nil
        }

        self.location = location
        self.metadata = metadata
        parsedOffset = 0
        parsedTail = Data()
        parser =
            switch location.provider {
            case .codex: CodexLogParser()
            case .claude: ClaudeLogParser()
            case .piAgent: PiLogParser()
            case .grok: GrokLogParser()
            }
        eventIndex = UsageEventIndex(since: historyStart)
        guard readLines(file, in: 0..<metadata.size) else {
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
            readAppendedLines()
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

    private mutating func readAppendedLines() {
        guard let file = try? FileDescriptor.open(FilePath(location.url.path), .readOnly) else {
            return
        }
        defer { try? file.close() }
        guard let metadata = UsageFileMetadata(fileDescriptor: file.rawValue) else {
            return
        }

        guard self.metadata.identity == metadata.identity,
            metadata.size >= self.metadata.size,
            parsedTailMatches(file)
        else {
            reread()
            return
        }

        // A failed read leaves the old size in place so the next pass retries from parsedOffset.
        if readLines(file, in: parsedOffset..<metadata.size) {
            self.metadata = metadata
        }
    }

    /// Parses every complete line in `offsets`; a trailing partial line waits for the next pass.
    /// Returns false when the range could not be read to its end.
    private mutating func readLines(_ file: FileDescriptor, in offsets: Range<UInt64>) -> Bool {
        var buffer = UnsafeMutableRawBufferPointer.allocate(
            byteCount: min(offsets.count, Self.readSize),
            alignment: 1
        )
        defer { buffer.deallocate() }
        // Bytes of an unfinished line kept at the front of `buffer`.
        var pending = 0
        var readOffset = offsets.lowerBound
        var decoder = UsageLineDecoder()
        defer { decodedLines += decoder.decodedLines }
        while readOffset < offsets.upperBound {
            if pending == buffer.count {
                let larger = UnsafeMutableRawBufferPointer.allocate(byteCount: buffer.count * 2, alignment: 1)
                larger.copyMemory(from: UnsafeRawBufferPointer(buffer))
                buffer.deallocate()
                buffer = larger
            }
            let space = buffer[pending..<min(buffer.count, pending + Int(clamping: offsets.upperBound - readOffset))]
            guard
                let count = try? file.read(
                    fromAbsoluteOffset: Int64(readOffset),
                    into: UnsafeMutableRawBufferPointer(rebasing: space)
                ),
                count > 0
            else {
                return false
            }
            readOffset += UInt64(count)
            pending += count
            let parsed = parseCompleteLines(UnsafeRawBufferPointer(rebasing: buffer[..<pending]), decoder: &decoder)
            parsedOffset += UInt64(parsed)
            pending -= parsed
            if let base = buffer.baseAddress, parsed > 0 {
                memmove(base, base + parsed, pending)
            }
        }
        return true
    }

    /// Parses each newline-terminated line in `bytes` and returns how many bytes those lines span.
    private mutating func parseCompleteLines(_ bytes: UnsafeRawBufferPointer, decoder: inout UsageLineDecoder) -> Int {
        guard let base = bytes.baseAddress else {
            return 0
        }
        var lineStart = 0
        while let newline = memchr(base + lineStart, 0x0A, bytes.count - lineStart) {
            let lineEnd = base.distance(to: newline)
            do {
                let line = UnsafeRawBufferPointer(rebasing: bytes[lineStart..<lineEnd])
                if let outcome = try parser.parse(line, decoder: &decoder) {
                    eventIndex.insert(outcome)
                }
            } catch {
                malformedLines += 1
            }
            lineStart = lineEnd + 1
        }
        if lineStart > 0 {
            let tail = bytes[max(lineStart - Self.parsedTailSize, 0)..<lineStart]
            parsedTail = Data((parsedTail + tail).suffix(Self.parsedTailSize))
        }
        return lineStart
    }

    private func parsedTailMatches(_ file: FileDescriptor) -> Bool {
        var tail = Data(count: parsedTail.count)
        let count = try? tail.withUnsafeMutableBytes {
            try file.read(fromAbsoluteOffset: Int64(parsedOffset) - Int64(parsedTail.count), into: $0)
        }
        return count == parsedTail.count && tail == parsedTail
    }
}

/// Every `.jsonl` file under the requested providers' log roots, tracked across refreshes by `fts` path.
struct UsageLogIndex {
    private let roots: [UsageLogLocation]
    private var logRoots: [UsageIngestionStats.LogRoot] = []
    private var trackedFiles: [String: TrackedUsageFile] = [:]
    private var indexedFrom = Date.distantPast

    init(roots: [UsageLogLocation]) {
        self.roots = roots
    }

    /// Events merged across every tracked file, with ingestion stats, as of the last `refresh`.
    func collect() -> (events: [UsageEvent], stats: UsageIngestionStats) {
        var merged = UsageEventIndex(since: indexedFrom)
        merged.reserveCapacity(trackedFiles.values.reduce(0) { $0 + $1.eventIndex.count })
        for (_, tracked) in trackedFiles.sorted(by: { $0.key < $1.key }) {
            merged.merge(tracked.eventIndex)
        }
        let events = merged.values
        let stats = UsageIngestionStats(
            logRoots: logRoots,
            trackedFiles: Self.tally(trackedFiles.values.map { ($0.location.provider, 1) }),
            events: Self.tally(events.map { ($0.provider, 1) }),
            decodedLines: Self.tally(trackedFiles.values.map { ($0.location.provider, $0.decodedLines) }),
            malformedLines: Self.tally(trackedFiles.values.map { ($0.location.provider, $0.malformedLines) }),
            unpricedModels: merged.unpricedModelIDs
        )
        return (events, stats)
    }

    /// Checks which roots exist, updates the tracked files of `providers`, drops all others, and
    /// reports whether the usage report may need rebuilding.
    mutating func refresh(since historyStart: Date, providers: Set<UsageProvider>) -> Bool {
        let logRoots = roots.map {
            UsageIngestionStats.LogRoot(
                provider: $0.provider,
                path: $0.url.path,
                exists: FileManager.default.fileExists(atPath: $0.url.path)
            )
        }
        var changed = logRoots != self.logRoots
        self.logRoots = logRoots
        if historyStart < indexedFrom {
            trackedFiles.removeAll(keepingCapacity: true)
            changed = true
        } else if historyStart > indexedFrom {
            trackedFiles = trackedFiles.mapValues { tracked in
                var tracked = tracked
                tracked.eventIndex.discard(before: historyStart)
                return tracked
            }
            changed = true
        }
        changed = scanLogs(roots.filter { providers.contains($0.provider) }, since: historyStart) || changed
        indexedFrom = historyStart
        return changed
    }

    private mutating func scanLogs(_ roots: [UsageLogLocation], since historyStart: Date) -> Bool {
        var seenPaths = Set<String>()
        var newFiles: [(path: String, location: UsageLogLocation)] = []
        var changed = false

        for root in roots {
            Self.walkJSONL(in: root.url.path) { path, metadata in
                // A file's events all predate its last write, so a file last written
                // before the window cannot contribute and is not worth opening.
                guard metadata.modificationDate >= historyStart else {
                    return
                }
                seenPaths.insert(path)
                if let fileChanged = trackedFiles[path]?.refresh(observed: metadata) {
                    changed = fileChanged || changed
                } else {
                    let location = UsageLogLocation(provider: root.provider, url: URL(fileURLWithPath: path))
                    newFiles.append((path, location))
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
        _ files: [(path: String, location: UsageLogLocation)],
        since historyStart: Date
    ) -> [String: TrackedUsageFile] {
        let trackedFiles = Mutex<[String: TrackedUsageFile]>([:])
        // Keep refresh synchronous so actor state cannot interleave while workers build files.
        DispatchQueue.concurrentPerform(iterations: files.count) { index in
            let (path, location) = files[index]
            guard let tracked = TrackedUsageFile.admit(location, since: historyStart) else {
                return
            }
            trackedFiles.withLock { $0[path] = tracked }
        }
        return trackedFiles.withLock { $0 }
    }

    private static func tally(_ counts: [(UsageProvider, Int)]) -> [UsageProvider: Int] {
        let zeros = Dictionary(uniqueKeysWithValues: UsageProvider.allCases.map { ($0, 0) })
        return counts.reduce(into: zeros) { totals, count in
            totals[count.0, default: 0] += count.1
        }
    }

    /// Walks `root` with `fts`, which hands back each entry's `stat` from the same
    /// directory read, so change detection costs no per-file syscalls or URL objects.
    /// A symlinked root is followed; symlinks below it are skipped.
    private static func walkJSONL(in root: String, _ body: (String, UsageFileMetadata) -> Void) {
        var paths: [UnsafeMutablePointer<CChar>?] = [strdup(root), nil]
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
            if path.hasSuffix(".jsonl") {
                body(path, metadata)
            }
        }
    }
}
