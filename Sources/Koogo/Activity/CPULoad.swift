import Darwin

/// Scheduler ticks accumulated since boot. Two readings a moment apart give the load over that moment.
struct CPUTicks: Equatable, Sendable {
    let user: UInt32
    let system: UInt32
    let idle: UInt32

    static func read() throws -> CPUTicks {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { throw ActivityReadFailure.cpu }
        let ticks = info.cpu_ticks
        return CPUTicks(user: ticks.0 &+ ticks.3, system: ticks.1, idle: ticks.2)
    }
}

/// Physical cores per performance level. A machine without levels counts every core as performance.
struct CPUCores: Equatable, Sendable {
    let performance: Int
    let efficiency: Int

    static func read() throws -> CPUCores {
        guard let performance: Int = Sysctl.value("hw.perflevel0.physicalcpu") ?? Sysctl.value("hw.physicalcpu")
        else { throw ActivityReadFailure.cpu }
        return CPUCores(performance: performance, efficiency: Sysctl.value("hw.perflevel1.physicalcpu") ?? 0)
    }
}

/// The share of time the cpu spent on user and kernel work between two tick readings.
struct CPULoad: Equatable, Sendable {
    let user: Double
    let system: Double
    let cores: CPUCores

    var total: Double { user + system }

    /// Counters wrap, so each delta is taken modulo the counter width. No elapsed ticks read as an idle cpu.
    init(from previous: CPUTicks, to next: CPUTicks, cores: CPUCores) {
        let user = Double(next.user &- previous.user)
        let system = Double(next.system &- previous.system)
        let idle = Double(next.idle &- previous.idle)
        let elapsed = user + system + idle
        self.user = elapsed > 0 ? user / elapsed : 0
        self.system = elapsed > 0 ? system / elapsed : 0
        self.cores = cores
    }
}
