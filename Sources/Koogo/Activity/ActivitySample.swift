enum ActivityReadFailure: Error {
    case cpu
    case memory
    case processes
}

struct ActivityCounters: Sendable {
    let ticks: CPUTicks
    let processes: ProcessScan

    static func read() throws -> ActivityCounters {
        ActivityCounters(ticks: try CPUTicks.read(), processes: try ProcessScan.read())
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

    func sample() async throws -> ActivitySample {
        let previous: ActivityCounters
        if let counters, SuspendingClock.now - counters.processes.taken < Self.countersExpireAfter {
            previous = counters
        } else {
            previous = try ActivityCounters.read()
            try await Task.sleep(for: .milliseconds(250))
        }
        let current = try ActivityCounters.read()
        counters = current
        return ActivitySample(
            taken: current.processes.taken,
            cpu: CPULoad(from: previous.ticks, to: current.ticks),
            cores: try CPUCores.read(),
            memory: try MemoryUsage.read(),
            gpu: GPULoad.read(),
            battery: BatteryState.read(),
            processes: AppProcessGroup.heaviest(
                in: current.processes,
                since: previous.processes,
                identity: AppIdentity.running
            )
        )
    }
}
