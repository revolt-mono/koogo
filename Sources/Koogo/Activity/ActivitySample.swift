enum ActivityReadFailure: Error {
    case cpu
    case memory
    case processes
}

struct ActivityCounters: Sendable {
    let ticks: CPUTicks
    let processes: ProcessScan

    static func read(after earlier: ActivityCounters?) throws -> ActivityCounters {
        ActivityCounters(ticks: try CPUTicks.read(), processes: try ProcessScan.read(after: earlier?.processes))
    }
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
    private static let countersExpireAfter: Duration = .seconds(10)

    private var counters: ActivityCounters?
    /// launch services answers for the latest groups' leaders by pid version; a process that is not yet a registered
    /// app is asked again.
    private var apps: [Int32: AppIdentity] = [:]

    func sample() async throws -> ActivitySample {
        let previous: ActivityCounters
        if let counters, SuspendingClock.now - counters.processes.taken < Self.countersExpireAfter {
            previous = counters
        } else {
            previous = try ActivityCounters.read(after: counters)
            try await Task.sleep(for: .milliseconds(250))
        }
        let current = try ActivityCounters.read(after: previous)
        counters = current
        var leaders: [Int32: AppIdentity] = [:]
        let processes = AppProcessGroup.heaviest(in: current.processes, since: previous.processes) { leader in
            let app = apps[leader.pidVersion] ?? AppIdentity.running(leader.pid)
            leaders[leader.pidVersion] = app
            return app
        }
        apps = leaders
        return ActivitySample(
            taken: current.processes.taken,
            cpu: CPULoad(from: previous.ticks, to: current.ticks),
            cores: try CPUCores.read(),
            memory: try MemoryUsage.read(),
            gpu: GPULoad.read(),
            battery: BatteryState.read(),
            processes: processes
        )
    }
}
