import Foundation
import System

struct AppendOnlyFile: LogFile {
  init(_ path: String, observed metadata: UsageFileMetadata) {
    self.path = path
    self.metadata = metadata
  }

  mutating func observe(_ observed: UsageFileMetadata) -> Bool {
    let wasReplaced =
      metadata.identity != observed.identity
        || observed.size < metadata.size
        || (observed.size == metadata.size && observed.modificationTime != metadata.modificationTime)
    if wasReplaced {
      state = .replaced
      return true
    }
    return state != .caughtUp || observed.size > metadata.size
  }

  mutating func read(restart: () -> Void, consume: (UnsafeRawBufferPointer) -> Void) -> Bool {
    guard let file = try? FileDescriptor.open(FilePath(path), .readOnly) else {
      return false
    }
    defer { try? file.close() }
    guard let current = UsageFileMetadata(file) else {
      return false
    }

    let restarted =
      state == .replaced || current.identity != metadata.identity || current.size < parsed.byteCount
        || !parsed.isIntact(in: file)
    if restarted {
      restart()
      parsed = ParsedPrefix()
    }
    let startOffset = parsed.byteCount
    let finished =
      startOffset >= current.size || readLines(file, in: startOffset..<current.size, consume: consume)
    metadata = current
    state = finished ? .caughtUp : .unfinished
    return finished || restarted || parsed.byteCount > startOffset
  }

  private enum ReadState {
    case caughtUp
    case unfinished
    case replaced
  }

  private struct ParsedPrefix {
    private(set) var byteCount: UInt64 = 0

    mutating func append(_ bytes: UnsafeRawBufferPointer) {
      guard !bytes.isEmpty else {
        return
      }
      tail = Data((tail + bytes.suffix(Self.tailSize)).suffix(Self.tailSize))
      byteCount += UInt64(bytes.count)
    }

    func isIntact(in file: FileDescriptor) -> Bool {
      guard !tail.isEmpty else {
        return true
      }
      var onDisk = Data(count: tail.count)
      let count = try? onDisk.withUnsafeMutableBytes {
        try file.read(fromAbsoluteOffset: Int64(byteCount) - Int64(tail.count), into: $0)
      }
      return count == tail.count && onDisk == tail
    }

    private static let tailSize = 64

    private var tail = Data()
  }

  private static let readSize = 1 << 18

  private let path: String
  private var metadata: UsageFileMetadata
  private var parsed = ParsedPrefix()
  private var state = ReadState.caughtUp

  private mutating func readLines(
    _ file: FileDescriptor,
    in offsets: Range<UInt64>,
    consume: (UnsafeRawBufferPointer) -> Void,
  ) -> Bool {
    var lines = LineBuffer(byteCount: min(offsets.count, Self.readSize))
    var readOffset = offsets.lowerBound
    while readOffset < offsets.upperBound {
      let space = lines.spaceToFill().prefix(Int(clamping: offsets.upperBound - readOffset))
      guard
        let count = try? file.read(
          fromAbsoluteOffset: Int64(readOffset),
          into: UnsafeMutableRawBufferPointer(rebasing: space),
        ),
        count > 0
      else {
        return false
      }
      readOffset += UInt64(count)
      parsed.append(lines.handOutLines(filled: count, consume: consume))
    }
    return true
  }
}
