import Darwin

/// scheduler ticks since boot; differences between readings yield load.
struct CPUTicks: Sendable {
    let user: UInt32
    let system: UInt32
    let idle: UInt32

    static func read() throws -> CPUTicks {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(MachHost.port, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { throw ActivityReadFailure.cpu }
        let ticks = info.cpu_ticks
        return CPUTicks(user: ticks.0 &+ ticks.3, system: ticks.1, idle: ticks.2)
    }
}

struct CPUCores: Sendable {
    let performance: Int
    let efficiency: Int

    static func read() throws -> CPUCores {
        guard let performance: Int32 = Sysctl.value("hw.perflevel0.physicalcpu") ?? Sysctl.value("hw.physicalcpu")
        else { throw ActivityReadFailure.cpu }
        let efficiency: Int32 = Sysctl.value("hw.perflevel1.physicalcpu") ?? 0
        return CPUCores(performance: Int(performance), efficiency: Int(efficiency))
    }
}

struct CPULoad: Sendable {
    let user: Double
    let system: Double

    var total: Double { user + system }

    /// tick counters wrap; zero elapsed ticks read as idle.
    init(from previous: CPUTicks, to next: CPUTicks) {
        let user = Double(next.user &- previous.user)
        let system = Double(next.system &- previous.system)
        let idle = Double(next.idle &- previous.idle)
        let elapsed = user + system + idle
        self.user = elapsed > 0 ? user / elapsed : 0
        self.system = elapsed > 0 ? system / elapsed : 0
    }
}
