import AppKit
import os

struct AppIdentity: Sendable {
  init(executablePath: String) {
    let components = (executablePath as NSString).pathComponents
    iconPath =
      components.lastIndex { $0.hasSuffix(".app") }
        .map { NSString.path(withComponents: Array(components[...$0])) } ?? executablePath
    name = ((iconPath as NSString).lastPathComponent as NSString).deletingPathExtension
  }

  private init(name: String, iconPath: String) {
    self.name = name
    self.iconPath = iconPath
  }

  let name: String
  let iconPath: String

  /// launch services resolves registered bundles even when executables run from code-sign clones.
  static func running(_ pid: pid_t) -> AppIdentity? {
    guard
      let app = NSRunningApplication(processIdentifier: pid),
      let name = app.localizedName,
      let bundlePath = app.bundleURL?.path
    else { return nil }
    return AppIdentity(name: name, iconPath: bundlePath)
  }
}

struct AppProcessMember: Sendable {
  let identity: ProcessIdentity
  let name: String
  let depth: Int
  let footprint: UInt64
  let cpu: Double
  let gpu: Double

  var pid: pid_t {
    identity.pid
  }
}

struct AppProcessGroup: Identifiable, Sendable {
  let id: pid_t
  let name: String
  let iconPath: String
  let members: [AppProcessMember]

  var footprint: UInt64 {
    members.reduce(0) { $0 + $1.footprint }
  }

  /// cpu cores used between scans; one busy core reads as 1.
  var cpu: Double {
    members.reduce(0) { $0 + $1.cpu }
  }

  /// fraction of the sample span spent on the group's gpu work.
  var gpu: Double {
    members.reduce(0) { $0 + $1.gpu }
  }

  static func heaviest(
    in scan: ProcessScan,
    since previous: ProcessScan,
    identity: (ProcessRecord) -> AppIdentity?,
  ) -> [AppProcessGroup] {
    let interval = ScanInterval(from: previous, to: scan)
    return Dictionary(grouping: scan.records, by: \.responsiblePID)
      .map { responsiblePID, members in
        (id: responsiblePID, members: members, footprint: members.reduce(0) { $0 + $1.footprint })
      }
      .sorted { ($1.footprint, $0.id) < ($0.footprint, $1.id) }
      .prefix(20)
      .map { group in
        let leader =
          group.members.first { $0.pid == group.id } ?? group.members.min { $0.launched < $1.launched }!
        let app = identity(leader) ?? AppIdentity(executablePath: leader.executablePath)
        return AppProcessGroup(
          id: group.id,
          name: app.name,
          iconPath: app.iconPath,
          members: nested(group.members, interval: interval),
        )
      }
  }

  func forceTerminate() {
    for member in members {
      do {
        try LibProc.forceKill(member.identity)
      } catch {
        Logger.activity.error("force terminate failed pid=\(member.pid): \(error, privacy: .public)")
      }
    }
  }

  private static func nested(_ records: [ProcessRecord], interval: ScanInterval) -> [AppProcessMember] {
    let children = Dictionary(grouping: records, by: \.parentPID)
    let pids = Set(records.map(\.pid))
    func nest(_ siblings: [ProcessRecord], depth: Int) -> [AppProcessMember] {
      siblings.sorted { ($1.footprint, $0.pid) < ($0.footprint, $1.pid) }
        .flatMap { record in
          let member = AppProcessMember(
            identity: record.identity,
            name: (record.executablePath as NSString).lastPathComponent,
            depth: depth,
            footprint: record.footprint,
            cpu: interval.load(of: record, \.cpuTime),
            gpu: interval.load(of: record, \.gpuTime),
          )
          return [member] + nest(children[record.pid] ?? [], depth: depth + 1)
        }
    }
    return nest(records.filter { !pids.contains($0.parentPID) }, depth: 0)
  }
}

private struct ScanInterval {
  init(from previous: ProcessScan, to scan: ProcessScan) {
    start = previous.taken
    elapsed = scan.taken - previous.taken
    earlier = previous.recordsByPID
  }

  func load(of record: ProcessRecord, _ time: KeyPath<ProcessRecord, Duration>) -> Double {
    let before = record.launched >= start ? .zero : earlier[record.pid]?[keyPath: time]
    guard elapsed > .zero, let before, record[keyPath: time] >= before else { return 0 }
    return (record[keyPath: time] - before) / elapsed
  }

  private let start: SuspendingClock.Instant
  private let elapsed: Duration
  private let earlier: [pid_t: ProcessRecord]
}
