import Darwin
import Foundation
import System

enum FileRead {
    case nothingNew
    case readLines
    case unreadable
}

protocol LineConsumer {
    /// The file no longer continues the bytes consumed so far; drop everything derived from them.
    mutating func restart()
    mutating func consume(_ line: UnsafeRawBufferPointer)
}

/// Incremental reader of a newline-delimited file. Complete lines are handed out once; a partial trailing line waits for its newline. A replaced or truncated file restarts from its first byte.
struct AppendOnlyFile: Sendable {
    private static var parsedTailSize: Int { 64 }
    private static var readSize: Int { 1 << 18 }

    private let path: String
    private var metadata: UsageFileMetadata
    private var parsedOffset: UInt64 = 0
    private var parsedTail = Data()
    private var needsRestart = false

    /// Starts from a directory walk's view of the file; the first read checks that view against the file itself.
    init(_ path: String, observed metadata: UsageFileMetadata) {
        self.path = path
        self.metadata = metadata
    }

    /// Records a directory walk's view of the file and reports whether a read is due.
    mutating func observe(_ observed: UsageFileMetadata) -> Bool {
        let wasReplaced =
            metadata.identity != observed.identity
            || observed.size < metadata.size
            || (observed.size == metadata.size && observed.modificationDate != metadata.modificationDate)
        if wasReplaced {
            needsRestart = true
            return true
        }
        return observed.size > metadata.size
    }

    mutating func read(into consumer: inout some LineConsumer) -> FileRead {
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
            consumer.restart()
            parsedOffset = 0
            parsedTail = Data()
            needsRestart = false
        }
        let startOffset = parsedOffset
        if parsedOffset < current.size {
            guard readLines(file, in: parsedOffset..<current.size, into: &consumer) else {
                return .unreadable
            }
        }
        metadata = current
        return restarted || parsedOffset > startOffset ? .readLines : .nothingNew
    }

    private mutating func readLines(
        _ file: FileDescriptor,
        in offsets: Range<UInt64>,
        into consumer: inout some LineConsumer
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
            let parsed = handOutCompleteLines(UnsafeRawBufferPointer(rebasing: buffer[..<pending]), into: &consumer)
            parsedOffset += UInt64(parsed)
            pending -= parsed
            if let base = buffer.baseAddress, parsed > 0 {
                memmove(base, base + parsed, pending)
            }
        }
        return true
    }

    /// Line buffers come straight from the VM system, which takes the pages back on release. Malloc would keep a freed buffer, which grows to fit the longest line, dirty for the life of the process.
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
        into consumer: inout some LineConsumer
    ) -> Int {
        guard let base = bytes.baseAddress else {
            return 0
        }
        var lineStart = 0
        while let newline = memchr(base + lineStart, 0x0A, bytes.count - lineStart) {
            let lineEnd = base.distance(to: newline)
            consumer.consume(UnsafeRawBufferPointer(rebasing: bytes[lineStart..<lineEnd]))
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
