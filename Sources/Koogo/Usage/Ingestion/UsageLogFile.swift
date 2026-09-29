import Darwin
import Foundation
import System

private struct UsageFileIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
}

struct UsageFileMetadata: Sendable {
    fileprivate let identity: UsageFileIdentity
    fileprivate let size: UInt64
    let modificationDate: Date

    init?(path: String) {
        var status = Darwin.stat()
        guard fstatat(AT_FDCWD, path, &status, 0) == 0 else {
            return nil
        }
        self.init(status: status)
    }

    fileprivate init?(fileDescriptor: Int32) {
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

/// State built from a log file's complete lines.
protocol UsageLogLines: Sendable {
    /// Throws for a line of a known record kind whose fields are unusable.
    mutating func consume(_ line: UnsafeRawBufferPointer) throws
    /// Empty state with the same settings, for a replaced file read again from its start.
    func restarted() -> Self
}

/// Line state that bills events, so its file is a usage log on its own.
protocol UsageEventLines: UsageLogLines {
    var events: UsageEventIndex { get set }
}

/// Events billed by one provider parser.
struct ParsedUsage<Parser: UsageLogParser>: UsageEventLines {
    private(set) var parser = Parser()
    var events: UsageEventIndex

    init(since historyStart: Date) {
        events = UsageEventIndex(since: historyStart)
    }

    mutating func consume(_ line: UnsafeRawBufferPointer) throws {
        if let outcome = try parser.parse(line) {
            events.insert(outcome)
        }
    }

    func restarted() -> Self {
        Self(since: events.historyStart)
    }
}

/// One log file read incrementally: bytes appended since the last pass are
/// parsed in place, while a rotated or truncated file is re-read from scratch.
struct UsageLogFile<Lines: UsageLogLines>: Sendable {
    private static var parsedTailSize: Int { 64 }
    private static var readSize: Int { 1 << 20 }

    private let url: URL
    private(set) var lines: Lines
    private(set) var malformedLines = 0
    private var metadata: UsageFileMetadata
    private var parsedOffset: UInt64
    private var parsedTail: Data

    init?(_ url: URL, lines: Lines) {
        guard let file = try? FileDescriptor.open(FilePath(url.path), .readOnly) else {
            return nil
        }
        defer { try? file.close() }
        guard let metadata = UsageFileMetadata(fileDescriptor: file.rawValue) else {
            return nil
        }

        self.url = url
        self.lines = lines
        self.metadata = metadata
        parsedOffset = 0
        parsedTail = Data()
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
        if let replacement = Self(url, lines: lines.restarted()) {
            self = replacement
        }
    }

    private mutating func readAppendedLines() {
        guard let file = try? FileDescriptor.open(FilePath(url.path), .readOnly) else {
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
            let parsed = parseCompleteLines(UnsafeRawBufferPointer(rebasing: buffer[..<pending]))
            parsedOffset += UInt64(parsed)
            pending -= parsed
            if let base = buffer.baseAddress, parsed > 0 {
                memmove(base, base + parsed, pending)
            }
        }
        return true
    }

    /// Parses each newline-terminated line in `bytes` and returns how many bytes those lines span.
    private mutating func parseCompleteLines(_ bytes: UnsafeRawBufferPointer) -> Int {
        guard let base = bytes.baseAddress else {
            return 0
        }
        var lineStart = 0
        while let newline = memchr(base + lineStart, 0x0A, bytes.count - lineStart) {
            let lineEnd = base.distance(to: newline)
            do {
                try lines.consume(UnsafeRawBufferPointer(rebasing: bytes[lineStart..<lineEnd]))
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

/// What the index tracks for each admitted log path.
protocol UsageLog: Sendable {
    var events: UsageEventIndex { get }
    var malformedLines: Int { get }
    /// Returns whether the log changed on disk since the last pass.
    mutating func refresh(observed metadata: UsageFileMetadata) -> Bool
    mutating func discard(before historyStart: Date)
}

extension UsageLogFile: UsageLog where Lines: UsageEventLines {
    var events: UsageEventIndex {
        lines.events
    }

    mutating func discard(before historyStart: Date) {
        lines.events.discard(before: historyStart)
    }
}
