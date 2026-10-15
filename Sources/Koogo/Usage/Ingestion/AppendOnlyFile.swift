import Darwin
import Foundation
import System

enum FileRead {
    case nothingNew
    /// the consumer received lines or a restart, even when the read later failed.
    case readLines
    /// the consumer received nothing; the next sync retries.
    case unreadable
}

/// delivers complete lines once, retaining a partial tail until newline; replacement or truncation restarts from byte zero.
struct AppendOnlyFile: Sendable {
    private static var parsedTailSize: Int { 64 }
    private static var readSize: Int { 1 << 18 }

    private let path: String
    private var metadata: UsageFileMetadata
    private var parsedOffset: UInt64 = 0
    private var parsedTail = Data()
    private var needsRestart = false
    private var needsReadRetry = false

    init(_ path: String, observed metadata: UsageFileMetadata) {
        self.path = path
        self.metadata = metadata
    }

    /// returns whether a read is due, including retrying an incomplete read.
    mutating func observe(_ observed: UsageFileMetadata) -> Bool {
        let wasReplaced =
            metadata.identity != observed.identity
            || observed.size < metadata.size
            || (observed.size == metadata.size && observed.modificationDate != metadata.modificationDate)
        if wasReplaced {
            needsRestart = true
            return true
        }
        return needsReadRetry || observed.size > metadata.size
    }

    /// restart invalidates all state derived from previously consumed bytes.
    mutating func read(restart: () -> Void, consume: (UnsafeRawBufferPointer) -> Void) -> FileRead {
        guard let file = try? FileDescriptor.open(FilePath(path), .readOnly) else {
            return .unreadable
        }
        defer { try? file.close() }
        guard let current = UsageFileMetadata(fileDescriptor: file.rawValue) else {
            return .unreadable
        }

        let restarted =
            needsRestart || current.identity != metadata.identity || current.size < parsedOffset
            || !parsedTailMatches(file)
        if restarted {
            restart()
            parsedOffset = 0
            parsedTail = Data()
            needsRestart = false
        }
        let startOffset = parsedOffset
        let finished =
            parsedOffset >= current.size || readLines(file, in: parsedOffset..<current.size, consume: consume)
        metadata = current
        needsReadRetry = !finished
        if restarted || parsedOffset > startOffset {
            return .readLines
        }
        return finished ? .nothingNew : .unreadable
    }

    private mutating func readLines(
        _ file: FileDescriptor,
        in offsets: Range<UInt64>,
        consume: (UnsafeRawBufferPointer) -> Void
    ) -> Bool {
        var buffer = Self.mapPages(byteCount: min(offsets.count, Self.readSize))
        defer { Self.unmapPages(buffer) }
        var pending = 0
        var readOffset = offsets.lowerBound
        while readOffset < offsets.upperBound {
            if pending == buffer.count {
                let larger = Self.mapPages(byteCount: buffer.count * 2)
                larger.copyMemory(from: UnsafeRawBufferPointer(buffer))
                Self.unmapPages(buffer)
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
            let parsed = handOutCompleteLines(UnsafeRawBufferPointer(rebasing: buffer[..<pending]), consume: consume)
            parsedOffset += UInt64(parsed)
            pending -= parsed
            if let base = buffer.baseAddress, parsed > 0 {
                memmove(base, base + parsed, pending)
            }
        }
        return true
    }

    /// unmapped pages return to the system; malloc can retain dirty buffers sized for the longest line.
    private static func mapPages(byteCount: Int) -> UnsafeMutableRawBufferPointer {
        guard let pages = mmap(nil, byteCount, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0),
            pages != MAP_FAILED
        else {
            preconditionFailure("out of address space for a \(byteCount)-byte line buffer")
        }
        return UnsafeMutableRawBufferPointer(start: pages, count: byteCount)
    }

    private static func unmapPages(_ buffer: UnsafeMutableRawBufferPointer) {
        munmap(buffer.baseAddress, buffer.count)
    }

    private mutating func handOutCompleteLines(
        _ bytes: UnsafeRawBufferPointer,
        consume: (UnsafeRawBufferPointer) -> Void
    ) -> Int {
        guard let base = bytes.baseAddress else {
            return 0
        }
        var lineStart = 0
        while let newline = memchr(base + lineStart, 0x0A, bytes.count - lineStart) {
            let lineEnd = base.distance(to: newline)
            consume(UnsafeRawBufferPointer(rebasing: bytes[lineStart..<lineEnd]))
            lineStart = lineEnd + 1
        }
        if lineStart > 0 {
            let tail = bytes[max(lineStart - Self.parsedTailSize, 0)..<lineStart]
            parsedTail = Data((parsedTail + tail).suffix(Self.parsedTailSize))
        }
        return lineStart
    }

    private func parsedTailMatches(_ file: FileDescriptor) -> Bool {
        guard !parsedTail.isEmpty else {
            return true
        }
        var tail = Data(count: parsedTail.count)
        let count = try? tail.withUnsafeMutableBytes {
            try file.read(fromAbsoluteOffset: Int64(parsedOffset) - Int64(parsedTail.count), into: $0)
        }
        return count == parsedTail.count && tail == parsedTail
    }
}
