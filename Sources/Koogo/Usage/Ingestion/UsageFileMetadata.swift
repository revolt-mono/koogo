import Darwin
import Foundation
import System

struct UsageFileMetadata: Equatable, Sendable {
  init?(_ file: FileDescriptor) {
    var status = Darwin.stat()
    guard fstat(file.rawValue, &status) == 0 else {
      return nil
    }
    self.init(status: status)
  }

  /// symlinks stay unresolved, as in directory walks.
  init?(path: String) {
    var status = Darwin.stat()
    guard lstat(path, &status) == 0 else {
      return nil
    }
    self.init(status: status)
  }

  init?(status: Darwin.stat) {
    guard status.st_size >= 0, status.st_mode & S_IFMT == S_IFREG else {
      return nil
    }
    identity = Identity(status)
    size = UInt64(status.st_size)
    modificationTime = UsageTimestamp(
      timeIntervalSince1970: TimeInterval(status.st_mtimespec.tv_sec)
        + TimeInterval(status.st_mtimespec.tv_nsec) / 1_000_000_000
    )
  }

  struct Identity: Equatable, Sendable {
    init(_ status: Darwin.stat) {
      device = UInt64(status.st_dev)
      inode = UInt64(status.st_ino)
    }

    let device: UInt64
    let inode: UInt64
  }

  let identity: Identity
  let size: UInt64
  let modificationTime: UsageTimestamp
}
