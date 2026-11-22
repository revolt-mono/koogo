import Darwin

struct LogDirectoryWalk {
  let root: UsageLogRoot
  let directory: String

  static func plan(roots: [UsageLogRoot], for changes: LogDirectoryWatcher.Changes) -> [Self] {
    guard case .directories(let directories) = changes else {
      return roots.map { Self(root: $0, directory: $0.path) }
    }
    var walks = [Self]()
    for directory in directories.sorted() where !walks.contains(where: { $0.covers(directory) }) {
      if let root = roots.first(where: { directory.isPath(within: $0.path) }) {
        walks.append(Self(root: root, directory: directory))
      }
    }
    return walks
  }

  func covers(_ path: String) -> Bool {
    path.isPath(within: directory)
  }

  func forEachLog(_ body: (_ path: String, _ metadata: UsageFileMetadata) -> Void) {
    let isRoot = directory == root.path
    guard isRoot || !Self.isHiddenOrMissing(directory, under: root.path) else {
      return
    }
    var paths: [UnsafeMutablePointer<CChar>?] = [strdup(directory), nil]
    defer { free(paths[0]) }
    guard let stream = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR | (isRoot ? FTS_COMFOLLOW : 0), nil) else {
      return
    }
    defer { fts_close(stream) }
    while let entry = fts_read(stream) {
      let info = Int32(entry.pointee.fts_info)
      let status = entry.pointee.fts_statp.pointee
      if
        entry.pointee.fts_level > 0,
        Self.isHidden(firstByte: UInt8(bitPattern: entry.pointee.fts_name), status: status)
      {
        if info == FTS_D {
          fts_set(stream, entry, FTS_SKIP)
        }
        continue
      }
      guard info == FTS_F, let metadata = UsageFileMetadata(status: status) else {
        continue
      }
      let path = String(cString: entry.pointee.fts_path)
      if root.format.match.matches(path: path) {
        body(path, metadata)
      }
    }
  }

  private static func isHiddenOrMissing(_ directory: String, under root: String) -> Bool {
    var path = root
    for component in directory.dropFirst(root.count + 1).split(separator: "/") {
      path += "/" + component
      var status = Darwin.stat()
      guard lstat(path, &status) == 0, !isHidden(firstByte: component.utf8.first ?? 0, status: status) else {
        return true
      }
    }
    return false
  }

  private static func isHidden(firstByte: UInt8, status: Darwin.stat) -> Bool {
    firstByte == UInt8(ascii: ".") || status.st_flags & UInt32(UF_HIDDEN) != 0
  }
}

extension String {
  func isPath(within directory: String) -> Bool {
    guard hasPrefix(directory) else {
      return false
    }
    return dropFirst(directory.count).first.map { $0 == "/" } ?? true
  }
}
