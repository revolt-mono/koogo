import Darwin
import Foundation

/// The `stat` fields that tell a rewritten log from an appended one.
struct UsageFileMetadata: Sendable {
    struct Identity: Equatable, Sendable {
        let device: UInt64
        let inode: UInt64
    }

    let identity: Identity
    let size: UInt64
    let modificationDate: Date

    init?(path: String) {
        var status = Darwin.stat()
        guard fstatat(AT_FDCWD, path, &status, 0) == 0 else {
            return nil
        }
        self.init(status: status)
    }

    init?(fileDescriptor: Int32) {
        var status = Darwin.stat()
        guard Darwin.fstat(fileDescriptor, &status) == 0 else {
            return nil
        }
        self.init(status: status)
    }

    init?(status: Darwin.stat) {
        guard status.st_size >= 0, status.st_mode & S_IFMT == S_IFREG else {
            return nil
        }
        identity = Identity(
            device: UInt64(status.st_dev),
            inode: UInt64(status.st_ino)
        )
        size = UInt64(status.st_size)
        modificationDate = Date(
            timeIntervalSince1970: TimeInterval(status.st_mtimespec.tv_sec)
                + TimeInterval(status.st_mtimespec.tv_nsec) / 1_000_000_000
        )
    }
}
