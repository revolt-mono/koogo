import Darwin
import Foundation
import System

/// retains a partial tail until newline; replacement or truncation restarts from byte zero.
struct AppendOnlyFile: LogFile {
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
        var buffer = PageBuffer(byteCount: min(offsets.count, Self.readSize))
        var pending = 0
        var readOffset = offsets.lowerBound
        while readOffset < offsets.upperBound {
            if pending == buffer.bytes.count {
                buffer.doubleCapacity()
            }
            let space = buffer.bytes[
                pending..<min(buffer.bytes.count, pending + Int(clamping: offsets.upperBound - readOffset))
            ]
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
            let parsed = handOutCompleteLines(
                UnsafeRawBufferPointer(rebasing: buffer.bytes[..<pending]),
                consume: consume
            )
            if parsed > 0 {
                let tail = buffer.bytes[max(parsed - Self.parsedTailSize, 0)..<parsed]
                parsedTail = Data((parsedTail + tail).suffix(Self.parsedTailSize))
                parsedOffset += UInt64(parsed)
                pending -= parsed
                memmove(buffer.bytes.baseAddress, buffer.bytes.baseAddress! + parsed, pending)
            }
        }
        return true
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
