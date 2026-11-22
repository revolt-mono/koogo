import Darwin

/// cpu and gpu times accumulate since process launch.
struct ProcessRecord: Sendable {
  let identity: ProcessIdentity
  let pidVersion: Int32
  let parentPID: pid_t
  let responsiblePID: pid_t
  let executablePath: String
  let launched: SuspendingClock.Instant
  let footprint: UInt64
  let cpuTime: Duration
  let gpuTime: Duration

  var pid: pid_t {
    identity.pid
  }
}

/// the suspending clock pauses during sleep, matching mach absolute launch timestamps.
struct ProcessScan: Sendable {
  let records: [ProcessRecord]
  let taken: SuspendingClock.Instant

  var recordsByPID: [pid_t: ProcessRecord] {
    Dictionary(records.map { ($0.pid, $0) }) { _, last in last }
  }

  /// a path stays as exec saw it, like the kernel's process name. the kernel hands a process back to itself once its
  /// responsible process exits.
  static func read(after earlier: ProcessScan?) throws -> ProcessScan {
    guard let pids = LibProc.currentUserPIDs() else { throw ActivityReadFailure.processes }
    let taken = SuspendingClock.now
    let gpuTimes = GPULoad.timePerProcess()
    // zombies stay listed until reaped, but their bsd info no longer reads.
    let running = pids.compactMap { pid in LibProc.bsdInfo(of: pid).map { (pid: pid, bsd: $0) } }
    let versions = Dictionary(running.map { ($0.pid, $0.bsd.pidVersion) }) { _, last in last }
    let earlier = earlier?.recordsByPID ?? [:]
    let unchanged = { (pid: pid_t) in earlier[pid].flatMap { $0.pidVersion == versions[pid] ? $0 : nil } }
    return ProcessScan(
      records: running.compactMap { pid, bsd in
        guard let usage = LibProc.resourceUsage(of: pid) else { return nil }
        let image = unchanged(pid)
        guard let executablePath = image?.executablePath ?? LibProc.executablePath(of: pid) else {
          return nil
        }
        let kept = image.flatMap { unchanged($0.responsiblePID)?.pid }
        let responsible = kept ?? responsiblePID?(pid) ?? pid
        return ProcessRecord(
          identity: ProcessIdentity(pid: pid, startTicks: usage.ri_proc_start_abstime),
          pidVersion: bsd.pidVersion,
          parentPID: bsd.parentPID,
          responsiblePID: responsible > 0 ? responsible : pid,
          executablePath: executablePath,
          launched: absoluteTimeZero + duration(ofTicks: usage.ri_proc_start_abstime),
          footprint: usage.ri_phys_footprint,
          cpuTime: duration(ofTicks: usage.ri_user_time + usage.ri_system_time),
          gpuTime: gpuTimes[pid] ?? .zero,
        )
      },
      taken: taken,
    )
  }

  private typealias ResponsiblePID = @convention(c) (pid_t) -> pid_t

  /// private libquarantine relation also used by activity monitor.
  private static let responsiblePID = PrivateSymbol.function(
    named: "responsibility_get_pid_responsible_for_pid",
    as: ResponsiblePID.self,
  )
  /// resource usage reports cpu and launch times in mach absolute units.
  private static let timebase: mach_timebase_info_data_t = {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return info
  }()

  private static let absoluteTimeZero = SuspendingClock.now - duration(ofTicks: mach_absolute_time())

  private static func duration(ofTicks ticks: UInt64) -> Duration {
    .nanoseconds(ticks * UInt64(timebase.numer) / UInt64(timebase.denom))
  }
}
