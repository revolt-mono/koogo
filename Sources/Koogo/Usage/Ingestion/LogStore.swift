import Foundation
import Synchronization

struct LogStore: ~Copyable {
  mutating func sync(roots: [UsageLogRoot], since windowStart: UsageTimestamp) {
    let windowMoved = moveWindow(to: windowStart)
    let rootsChanged = updateRoots(roots)
    let reported = takeReportedChanges(for: roots)
    let changes = windowMoved || rootsChanged ? .everything : reported
    let walks = LogDirectoryWalk.plan(roots: roots, for: changes)

    var unobserved = entries
    entries = Dictionary(minimumCapacity: unobserved.count)
    var unopened = [(path: String, metadata: UsageFileMetadata, root: UsageLogRoot)]()
    func observe(_ path: String, _ metadata: UsageFileMetadata, _ entry: consuming Entry) {
      if metadata.modificationTime < windowStart {
        entry.log = nil
      } else if entry.log == nil {
        unopened.append((path, metadata, entry.root))
      } else {
        entry.log?.sync(observed: metadata, since: windowStart)
      }
      entries[path] = entry
    }

    for walk in walks {
      walk.forEachLog { path, metadata in
        observe(path, metadata, Entry(root: walk.root, log: unobserved.removeValue(forKey: path)?.log))
      }
    }
    // fsevents reports an appended log only once its writer closes it.
    if case .directories = changes {
      // popping moves each log out, so syncing it appends in place instead of copying its events.
      while let (path, entry) = unobserved.popFirst() {
        if !walks.contains(where: { $0.covers(path) }), let metadata = UsageFileMetadata(path: path) {
          observe(path, metadata, entry)
        }
      }
    }
    for (path, root, opening) in Self.open(unopened, since: windowStart) {
      switch opening {
      case .opened(let log):
        entries[path] = Entry(root: root, log: log)
      case .declined:
        entries[path] = nil
      case .unreadable:
        break
      }
    }
  }

  func collect(_ visit: (UsageEvent) -> Void) -> UsageIngestionStats {
    var trackedFiles = EnumMap<Provider, Int> { _ in 0 }
    var malformedLines = EnumMap<Provider, Int> { _ in 0 }
    var unpricedModels = Set<ModelID>()
    var indexes = [UsageEventIndex]()
    // path order makes an exact tie between logs keep the first path's copy.
    for (_, entry) in entries.sorted(by: { $0.key < $1.key }) {
      guard let log = entry.log else {
        continue
      }
      trackedFiles[entry.root.provider] += 1
      malformedLines[entry.root.provider] += log.droppedInput.malformedLines
      unpricedModels.formUnion(log.droppedInput.unpricedModels)
      indexes.append(log.events)
    }

    var events = EnumMap<Provider, Int> { _ in 0 }
    UsageEventIndex.forEachUnique(in: indexes) { event in
      events[event.provider] += 1
      visit(event)
    }
    return UsageIngestionStats(
      logRoots: logRoots,
      trackedFiles: trackedFiles,
      events: events,
      malformedLines: malformedLines,
      unpricedModels: unpricedModels.sorted().map(\.rawValue),
    )
  }

  private struct Entry: Sendable {
    let root: UsageLogRoot
    /// a resumed writer updates the modification time without a directory event.
    var log: any TrackedLog?
  }

  private var entries = [String: Entry]()
  private var logRoots = [UsageIngestionStats.LogRoot]()
  private var windowStart = UsageTimestamp(.distantPast)
  private var watcher: LogDirectoryWatcher?

  private static func open(
    _ files: [(path: String, metadata: UsageFileMetadata, root: UsageLogRoot)],
    since windowStart: UsageTimestamp,
  ) -> [(path: String, root: UsageLogRoot, opening: UsageLogFormat.Opening)] {
    let opened = Mutex([(path: String, root: UsageLogRoot, opening: UsageLogFormat.Opening)]())
    let nextFile = Atomic(0)
    DispatchQueue.concurrentPerform(iterations: min(files.count, 4)) { _ in
      while case let index = nextFile.wrappingAdd(1, ordering: .relaxed).oldValue, index < files.count {
        let (path, metadata, root) = files[index]
        let opening = root.format.open(path, metadata, windowStart)
        opened.withLock { $0.append((path, root, opening)) }
      }
    }
    return opened.withLock { $0 }
  }

  private mutating func moveWindow(to windowStart: UsageTimestamp) -> Bool {
    guard windowStart != self.windowStart else {
      return false
    }
    if windowStart < self.windowStart {
      entries.removeAll(keepingCapacity: true)
    } else {
      var index = entries.startIndex
      while index != entries.endIndex {
        entries.values[index].log?.discard(before: windowStart)
        entries.formIndex(after: &index)
      }
    }
    self.windowStart = windowStart
    return true
  }

  private mutating func updateRoots(_ roots: [UsageLogRoot]) -> Bool {
    let logRoots = roots.map {
      UsageIngestionStats.LogRoot(
        provider: $0.provider,
        path: $0.path,
        exists: FileManager.default.fileExists(atPath: $0.path),
      )
    }
    defer { self.logRoots = logRoots }
    return logRoots != self.logRoots
  }

  private mutating func takeReportedChanges(for roots: [UsageLogRoot]) -> LogDirectoryWatcher.Changes {
    let paths = roots.map(\.path)
    guard let watcher, watcher.watches(paths) else {
      watcher = LogDirectoryWatcher(roots: paths)
      return .everything
    }
    return watcher.takeChanges()
  }
}
