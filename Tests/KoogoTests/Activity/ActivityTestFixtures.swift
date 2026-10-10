@testable import Koogo

func activitySample(
    cpu: Double = 0.3,
    memoryUsed: UInt64 = 32 << 30,
    gpu: Double? = 0.5,
    draw: Double? = 10
) -> ActivitySample {
    let busy = UInt32((cpu * 100).rounded())
    return ActivitySample(
        cpu: CPULoad(
            from: CPUTicks(user: 0, system: 0, idle: 0),
            to: CPUTicks(user: busy, system: 0, idle: 100 - busy),
            cores: CPUCores(performance: 8, efficiency: 4)
        ),
        memory: MemoryUsage(total: 64 << 30, app: memoryUsed, wired: 0, compressed: 0),
        gpu: gpu.map { GPULoad(name: "Test GPU", utilization: $0, renderer: $0, tiler: 0, memory: 1 << 30) },
        battery: draw.flatMap { batteryState(draw: $0) },
        processes: []
    )
}

/// A charging battery; `properties` overrides keys at the top level.
func batteryState(draw: Double = 10, properties: [String: Any] = [:]) -> BatteryState? {
    BatteryState(properties: batteryProperties(draw: draw).merging(properties) { _, override in override })
}

func batteryProperties(draw: Double = 10) -> [String: Any] {
    [
        "CurrentCapacity": 80,
        "MaxCapacity": 100,
        "ExternalConnected": true,
        "IsCharging": true,
        "TimeRemaining": 80,
        "CycleCount": 212,
        "Amperage": -1_000,
        "Voltage": 12_000,
        "PowerTelemetryData": ["SystemLoad": Int(draw * 1_000)],
        "BatteryData": ["AppleRawMaxCapacity": 6_186, "DesignCapacity": 6_249],
    ]
}
