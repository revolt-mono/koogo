enum ActivityReadFailure: Error {
    case cpu
    case memory
    case processes
}

/// Counters that only accumulate: cpu ticks since boot and each process's cpu and gpu time. Two readings a moment apart yield that moment's loads.
struct ActivityCounters: Sendable {
    let ticks: CPUTicks
    let processes: ProcessScan

    var taken: SuspendingClock.Instant { processes.taken }

    static func read() throws -> ActivityCounters {
        ActivityCounters(ticks: try CPUTicks.read(), processes: try ProcessScan.read())
    }
}

/// One moment of the machine. The gpu is absent only when the machine exposes no accelerator statistics, the battery only when there is none.
struct ActivitySample: Equatable, Sendable {
    let cpu: CPULoad
    let memory: MemoryUsage
    let gpu: GPULoad?
    let battery: BatteryState?
    let processes: [AppProcessGroup]
}

extension ActivitySample {
    /// Loads over the span between two counter readings, with the memory, gpu, and battery state at its end.
    init(from previous: ActivityCounters, to current: ActivityCounters) throws {
        cpu = CPULoad(from: previous.ticks, to: current.ticks, cores: try CPUCores.read())
        memory = try MemoryUsage.read()
        gpu = GPULoad.read()
        battery = BatteryState.read()
        processes = AppProcessGroup.heaviest(
            in: current.processes,
            since: previous.processes,
            identity: AppIdentity.running
        )
    }
}

/// Reads the machine once per call. A call without a recent earlier reading pauses briefly to take both ends of the span.
actor ActivitySampler {
    /// Counters older than this span a gap between two openings of the panel, not a moment of load.
    private static let countersExpireAfter: Duration = .seconds(10)

    private var counters: ActivityCounters?

    func sample() async throws -> ActivitySample {
        let previous: ActivityCounters
        if let counters, SuspendingClock.now - counters.taken < Self.countersExpireAfter {
            previous = counters
        } else {
            previous = try ActivityCounters.read()
            try await Task.sleep(for: .milliseconds(250))
        }
        let current = try ActivityCounters.read()
        counters = current
        return try ActivitySample(from: previous, to: current)
    }
}
