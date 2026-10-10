import IOKit

struct BatteryState: Equatable, Sendable {
    /// Estimates are absent until the charger or load settles.
    enum Supply: Equatable, Sendable {
        case charging(timeToFull: Duration?)
        /// External power with the battery held: full, or parked by the charge limit.
        case external
        case discharging(timeToEmpty: Duration?)
    }

    let charge: Double
    let supply: Supply
    /// Watts the system draws. Absent without power telemetry on external power, where the battery's own current says nothing about the system.
    let draw: Double?
    /// Full capacity over design capacity, capped at one for a fresh cell.
    let health: Double
    let cycles: Int

    /// The driver marks an unknown estimate with all ones.
    private static let unknownMinutes = 65535

    /// Nil when the machine has no battery, which only means the battery goes unshown.
    static func read() -> BatteryState? {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
            let properties = properties?.takeRetainedValue() as? [String: Any]
        else { return nil }
        return BatteryState(properties: properties)
    }

    /// Nil when the registry entry lacks the battery figures, as a battery-less machine's placeholder entry does. Capacities sit under `BatteryData` on Apple silicon and at the top level on Intel.
    init?(properties: [String: Any]) {
        let batteryData = properties["BatteryData"] as? [String: Any] ?? [:]
        guard
            let current = properties["CurrentCapacity"] as? Int, let maximum = properties["MaxCapacity"] as? Int,
            maximum > 0,
            let fullCapacity = (batteryData["AppleRawMaxCapacity"] ?? properties["AppleRawMaxCapacity"]) as? Int,
            let designCapacity = (batteryData["DesignCapacity"] ?? properties["DesignCapacity"]) as? Int,
            designCapacity > 0, let cycles = properties["CycleCount"] as? Int,
            let external = properties["ExternalConnected"] as? Bool, let charging = properties["IsCharging"] as? Bool
        else { return nil }
        let estimate = (properties["TimeRemaining"] as? Int)
            .flatMap { $0 > 0 && $0 < Self.unknownMinutes ? Duration.seconds($0 * 60) : nil }
        charge = Double(current) / Double(maximum)
        supply =
            switch (external, charging) {
            case (true, true): .charging(timeToFull: estimate)
            case (true, false): .external
            case (false, _): .discharging(timeToEmpty: estimate)
            }
        let telemetry = properties["PowerTelemetryData"] as? [String: Any]
        if let milliwatts = telemetry?["SystemLoad"] as? Int {
            draw = Double(milliwatts) / 1000
        } else if case .discharging = supply, let milliamps = properties["Amperage"] as? Int,
            let millivolts = properties["Voltage"] as? Int
        {
            draw = Double(abs(milliamps * millivolts)) / 1_000_000
        } else {
            draw = nil
        }
        health = min(Double(fullCapacity) / Double(designCapacity), 1)
        self.cycles = cycles
    }
}
