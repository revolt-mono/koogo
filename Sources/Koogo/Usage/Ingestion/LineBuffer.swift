import Darwin

struct LineBuffer: ~Copyable {
  init(byteCount: Int) {
    pages = PageBuffer(byteCount: byteCount)
  }

  mutating func spaceToFill() -> UnsafeMutableRawBufferPointer {
    if partialLineStart > 0 {
      memmove(pages.bytes.baseAddress, pages.bytes.baseAddress! + partialLineStart, filledCount - partialLineStart)
      filledCount -= partialLineStart
      partialLineStart = 0
    }
    if filledCount == pages.bytes.count {
      pages.doubleCapacity()
    }
    return UnsafeMutableRawBufferPointer(rebasing: pages.bytes[filledCount...])
  }

  /// the returned bytes stay valid until the next `spaceToFill()`.
  @discardableResult
  mutating func handOutLines(filled count: Int, consume: (UnsafeRawBufferPointer) -> Void) -> UnsafeRawBufferPointer {
    let base = pages.bytes.baseAddress!
    var lineStart = partialLineStart
    var unscanned = filledCount
    filledCount += count
    while let newline = memchr(base + unscanned, 0x0A, filledCount - unscanned) {
      let lineEnd = base.distance(to: newline)
      consume(UnsafeRawBufferPointer(start: base + lineStart, count: lineEnd - lineStart))
      lineStart = lineEnd + 1
      unscanned = lineStart
    }
    let handedOut = UnsafeRawBufferPointer(start: base + partialLineStart, count: lineStart - partialLineStart)
    partialLineStart = lineStart
    return handedOut
  }

  private var pages: PageBuffer
  private var partialLineStart = 0
  private var filledCount = 0
}
