import Darwin

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
