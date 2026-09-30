import Darwin
import Foundation
import System

struct UsageLogFile<Parser: UsageLogParser>: UsageLog {
    private static var parsedTailSize: Int { 64 }
    private static var readSize: Int { 1 << 18 }

    private let url: URL
    private let freshParser: Parser
    private(set) var parser: Parser
    private(set) var events: UsageEventIndex
    private(set) var malformedLines = 0
    private var metadata: UsageFileMetadata
    private var parsedOffset: UInt64
    private var parsedTail: Data

    init?(_ url: URL, parser: Parser, since historyStart: Date) {
        guard let file = try? FileDescriptor.open(FilePath(url.path), .readOnly) else {
            return nil
        }
        defer { try? file.close() }
        guard let metadata = UsageFileMetadata(fileDescriptor: file.rawValue) else {
            return nil
        }

        self.url = url
        freshParser = parser
        self.parser = parser
        events = UsageEventIndex(since: historyStart)
        self.metadata = metadata
        parsedOffset = 0
        parsedTail = Data()
        guard readLines(file, in: 0..<metadata.size) else {
            return nil
        }
    }

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

    mutating func discard(before historyStart: Date) {
        events.discard(before: historyStart)
    }

    private mutating func reread() {
        if let replacement = Self(url, parser: freshParser, since: events.historyStart) {
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

        if readLines(file, in: parsedOffset..<metadata.size) {
            self.metadata = metadata
        }
    }

    private mutating func readLines(_ file: FileDescriptor, in offsets: Range<UInt64>) -> Bool {
        var buffer = UnsafeMutableRawBufferPointer.allocate(
            byteCount: min(offsets.count, Self.readSize),
            alignment: 1
        )
        defer { buffer.deallocate() }
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

    private mutating func parseCompleteLines(_ bytes: UnsafeRawBufferPointer) -> Int {
        guard let base = bytes.baseAddress else {
            return 0
        }
        var lineStart = 0
        while let newline = memchr(base + lineStart, 0x0A, bytes.count - lineStart) {
            let lineEnd = base.distance(to: newline)
            do {
                if let outcome = try parser.parse(UnsafeRawBufferPointer(rebasing: bytes[lineStart..<lineEnd])) {
                    events.insert(outcome)
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
