@testable import Koogo

func activitySample(cpu: Double = 0.3, memoryUsed: UInt64 = 32 << 30, gpu: Double? = 0.5) -> ActivitySample {
    let busy = UInt32((cpu * 100).rounded())
    return ActivitySample(
        cpu: CPULoad(
            from: CPUTicks(user: 0, system: 0, idle: 0),
            to: CPUTicks(user: busy, system: 0, idle: 100 - busy),
            cores: CPUCores(performance: 8, efficiency: 4)
        ),
        memory: MemoryUsage(total: 64 << 30, app: memoryUsed, wired: 0, compressed: 0),
        gpu: gpu.map { GPULoad(name: "Test GPU", utilization: $0, memory: 1 << 30) },
        processes: []
    )
}
