@testable import Koogo

extension ActivitySample {
  static func stub(
    cpu: Double = 0.3,
    gpu: Double? = 0.5,
    draw: Double? = 10,
  ) -> Self {
    let busy = UInt32((cpu * 100).rounded())
    return ActivitySample(
      taken: .now,
      cpu: CPULoad(
        from: CPUTicks(user: 0, system: 0, idle: 0),
        to: CPUTicks(user: busy, system: 0, idle: 100 - busy),
      ),
      cores: .hybrid(performance: 8, efficiency: 4),
      memory: MemoryUsage(total: 64 << 30, app: 32 << 30, wired: 0, compressed: 0),
      gpu: gpu.map { GPULoad(name: "Test GPU", utilization: $0, renderer: $0, tiler: 0) },
      battery: draw.flatMap { BatteryState.stub(draw: $0) },
      processes: [],
    )
  }
}

extension BatteryState {
  static func stub(draw: Double = 10, properties: [String: Any] = [:]) -> Self? {
    BatteryState(properties: stubProperties(draw: draw).merging(properties) { _, override in override })
  }

  static func stubProperties(draw: Double = 10) -> [String: Any] {
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
}
