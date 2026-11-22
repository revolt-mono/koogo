import CZstd
import Darwin
import Foundation
import System

/// a zstd archive is written whole and never appended.
struct CompressedFile: LogFile {
  init(_ path: String, observed metadata: UsageFileMetadata) {
    self.path = path
    self.metadata = metadata
  }

  mutating func observe(_ observed: UsageFileMetadata) -> Bool {
    observed != metadata
  }

  /// a corrupt archive keeps the lines decoded before the damage; rereading an unchanged file cannot recover more.
  mutating func read(restart: () -> Void, consume: (UnsafeRawBufferPointer) -> Void) -> Bool {
    guard let file = try? FileDescriptor.open(FilePath(path), .readOnly) else {
      return false
    }
    defer { try? file.close() }
    guard let current = UsageFileMetadata(file) else {
      return false
    }
    metadata = current
    restart()
    Self.decode(file, consume: consume)
    return true
  }

  /// the decoder's window spans megabytes, which malloc keeps dirty after free; unmapped pages return to the system.
  /// the 16-byte header preserves malloc alignment. zstd never frees null.
  private static var mappedMemory: ZSTD_customMem {
    ZSTD_customMem(
      customAlloc: { _, size in
        let length = size + 16
        guard
          let pages = mmap(nil, length, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0),
          pages != MAP_FAILED
        else {
          return nil
        }
        pages.storeBytes(of: length, as: Int.self)
        return pages + 16
      },
      customFree: { _, memory in
        let pages = memory! - 16
        munmap(pages, pages.load(as: Int.self))
      },
      opaque: nil,
    )
  }

  private let path: String
  private var metadata: UsageFileMetadata

  private static func decode(_ file: FileDescriptor, consume: (UnsafeRawBufferPointer) -> Void) {
    guard let stream = ZSTD_createDStream_advanced(mappedMemory) else {
      return
    }
    defer { ZSTD_freeDStream(stream) }
    let compressed = PageBuffer(byteCount: ZSTD_DStreamInSize())
    var lines = LineBuffer(byteCount: ZSTD_DStreamOutSize())
    while let count = try? file.read(into: compressed.bytes), count > 0 {
      var input = ZSTD_inBuffer(src: compressed.bytes.baseAddress, size: count, pos: 0)
      // a full output buffer holds back decoded bytes even after the input is consumed.
      var isOutputFilled = true
      while input.pos < input.size || isOutputFilled {
        let space = lines.spaceToFill()
        var output = ZSTD_outBuffer(dst: space.baseAddress, size: space.count, pos: 0)
        guard ZSTD_isError(ZSTD_decompressStream(stream, &output, &input)) == 0 else {
          return
        }
        isOutputFilled = output.pos == output.size
        lines.handOutLines(filled: output.pos, consume: consume)
      }
    }
  }
}
