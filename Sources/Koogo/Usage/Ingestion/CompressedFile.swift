import CZstd
import Darwin
import Foundation
import System

/// a zstd archive is written whole and never appended, so any change rereads it from the start.
struct CompressedFile: LogFile {
    private let path: String
    private var metadata: UsageFileMetadata

    init(_ path: String, observed metadata: UsageFileMetadata) {
        self.path = path
        self.metadata = metadata
    }

    mutating func observe(_ observed: UsageFileMetadata) -> Bool {
        observed.identity != metadata.identity || observed.size != metadata.size
            || observed.modificationDate != metadata.modificationDate
    }

    /// a corrupt archive keeps the lines decoded before the damage; rereading an unchanged file cannot recover more.
    mutating func read(restart: () -> Void, consume: (UnsafeRawBufferPointer) -> Void) -> Bool {
        guard let file = try? FileDescriptor.open(FilePath(path), .readOnly) else {
            return false
        }
        defer { try? file.close() }
        guard let current = UsageFileMetadata(fileDescriptor: file.rawValue) else {
            return false
        }
        metadata = current
        restart()
        Self.decode(file, consume: consume)
        return true
    }

    private static func decode(_ file: FileDescriptor, consume: (UnsafeRawBufferPointer) -> Void) {
        guard let stream = ZSTD_createDStream_advanced(mappedMemory) else {
            return
        }
        defer { ZSTD_freeDStream(stream) }
        let compressed = PageBuffer(byteCount: ZSTD_DStreamInSize())
        var lines = PageBuffer(byteCount: ZSTD_DStreamOutSize())
        var pending = 0
        while let count = try? file.read(into: compressed.bytes), count > 0 {
            var input = ZSTD_inBuffer(src: compressed.bytes.baseAddress, size: count, pos: 0)
            // a full output buffer holds back decoded bytes even after the input is consumed.
            var outputFilled = true
            while input.pos < input.size || outputFilled {
                if pending == lines.bytes.count {
                    lines.doubleCapacity()
                }
                var output = ZSTD_outBuffer(
                    dst: lines.bytes.baseAddress! + pending,
                    size: lines.bytes.count - pending,
                    pos: 0
                )
                guard ZSTD_isError(ZSTD_decompressStream(stream, &output, &input)) == 0 else {
                    return
                }
                outputFilled = output.pos == output.size
                pending += output.pos
                let parsed = handOutCompleteLines(
                    UnsafeRawBufferPointer(rebasing: lines.bytes[..<pending]),
                    consume: consume
                )
                pending -= parsed
                memmove(lines.bytes.baseAddress, lines.bytes.baseAddress! + parsed, pending)
            }
        }
    }

    /// the decoder's window spans megabytes, which malloc keeps dirty after free; unmapped pages return to the system.
    /// each mapping leads with its 16-byte length, keeping the returned memory aligned like malloc's. zstd never frees
    /// null.
    private static var mappedMemory: ZSTD_customMem {
        ZSTD_customMem(
            customAlloc: { _, size in
                let length = size + 16
                guard let pages = mmap(nil, length, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0),
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
            opaque: nil
        )
    }
}
