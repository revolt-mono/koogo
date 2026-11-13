import Darwin
import Foundation

/// delivers complete lines once; a restart invalidates all state derived from previously consumed bytes.
protocol LogFile: Sendable {
  /// returns whether a read is due.
  mutating func observe(_ observed: UsageFileMetadata) -> Bool
  /// returns false when the consumer received nothing because the file could not be read; the next sync retries.
  mutating func read(restart: () -> Void, consume: (UnsafeRawBufferPointer) -> Void) -> Bool
}

/// unmapped pages return to the system; malloc can retain dirty buffers sized for the longest line.
struct PageBuffer: ~Copyable {
  init(byteCount: Int) {
    bytes = Self.map(byteCount: byteCount)
  }

  deinit {
    munmap(bytes.baseAddress, bytes.count)
  }

  private(set) var bytes: UnsafeMutableRawBufferPointer

  mutating func doubleCapacity() {
    let larger = Self.map(byteCount: bytes.count * 2)
    larger.copyMemory(from: UnsafeRawBufferPointer(bytes))
    munmap(bytes.baseAddress, bytes.count)
    bytes = larger
  }

  /// hands out the complete lines among the first `count` bytes and returns the bytes consumed;
  /// a trailing partial line stays.
  func handOutCompleteLines(first count: Int, consume: (UnsafeRawBufferPointer) -> Void) -> Int {
    guard let base = bytes.baseAddress else {
      return 0
    }
    var lineStart = 0
    while let newline = memchr(base + lineStart, 0x0A, count - lineStart) {
      let lineEnd = base.distance(to: newline)
      consume(UnsafeRawBufferPointer(rebasing: bytes[lineStart..<lineEnd]))
      lineStart = lineEnd + 1
    }
    return lineStart
  }

  private static func map(byteCount: Int) -> UnsafeMutableRawBufferPointer {
    guard
      let pages = mmap(nil, byteCount, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0),
      pages != MAP_FAILED
    else {
      preconditionFailure("out of address space for a \(byteCount)-byte line buffer")
    }
    return UnsafeMutableRawBufferPointer(start: pages, count: byteCount)
  }
}
