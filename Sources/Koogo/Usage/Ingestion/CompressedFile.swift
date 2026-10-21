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
    mutating func read(restart: () -> Void, consume: (UnsafeRawBufferPointer) -> Void) -> FileRead {
        guard let file = try? FileDescriptor.open(FilePath(path), .readOnly) else {
            return .unreadable
        }
        defer { try? file.close() }
        guard let current = UsageFileMetadata(fileDescriptor: file.rawValue) else {
            return .unreadable
        }
        metadata = current
        restart()
        Self.decode(file, consume: consume)
        return .readLines
    }

    private static func decode(_ file: FileDescriptor, consume: (UnsafeRawBufferPointer) -> Void) {
        guard let stream = ZSTD_createDStream() else {
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
}
