enum ActivityReadFailure: Error {
  case cpu
  case memory
  case processes
}

struct ActivitySample: Sendable {
  let taken: SuspendingClock.Instant
  let cpu: CPULoad
  let cores: CPUCores
  let memory: MemoryUsage
  let gpu: GPULoad?
  let battery: BatteryState?
  let processes: [AppProcessGroup]
}

actor ActivitySampler {
  func sample() async throws -> ActivitySample {
    let previous = try await baseline()
    let current = try Counters.read(after: previous)
    counters = current
    let processes = heaviestGroups(in: current.processes, since: previous.processes)
    return ActivitySample(
      taken: current.processes.taken,
      cpu: CPULoad(from: previous.ticks, to: current.ticks),
      cores: try CPUCores.read(),
      memory: try MemoryUsage.read(),
      gpu: GPULoad.read(),
      battery: BatteryState.read(),
      processes: processes,
    )
  }

  private struct Counters {
    let ticks: CPUTicks
    let processes: ProcessScan

    static func read(after earlier: Counters?) throws -> Counters {
      Counters(ticks: try CPUTicks.read(), processes: try ProcessScan.read(after: earlier?.processes))
    }
  }

  private static let countersExpireAfter = Duration.seconds(10)

  private var counters: Counters?
  /// launch services answers for the latest groups' leaders by pid version; a process that is not yet a registered
  /// app is asked again.
  private var apps = [Int32: AppIdentity]()

  private func baseline() async throws -> Counters {
    if let counters, SuspendingClock.now - counters.processes.taken < Self.countersExpireAfter {
      return counters
    }
    let fresh = try Counters.read(after: counters)
    try await Task.sleep(for: .milliseconds(250))
    return fresh
  }

  private func heaviestGroups(in scan: ProcessScan, since previous: ProcessScan) -> [AppProcessGroup] {
    var leaders = [Int32: AppIdentity]()
    let groups = AppProcessGroup.heaviest(in: scan, since: previous) { leader in
      let app = apps[leader.pidVersion] ?? AppIdentity.running(leader.pid)
      leaders[leader.pidVersion] = app
      return app
    }
    apps = leaders
    return groups
  }
}
