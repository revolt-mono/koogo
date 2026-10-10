import XCTest

@testable import Koogo

final class BatteryStateTests: XCTestCase {
    func testAChargingBatteryReadsItsChargeEstimateDrawHealthAndCycles() throws {
        let battery = try XCTUnwrap(batteryState(draw: 14.3))

        XCTAssertEqual(battery.charge, 0.8)
        XCTAssertEqual(battery.supply, .charging(timeToFull: .seconds(80 * 60)))
        XCTAssertEqual(try XCTUnwrap(battery.draw), 14.3, accuracy: 0.0001)
        XCTAssertEqual(battery.health, 0.98992, accuracy: 0.0001)
        XCTAssertEqual(battery.cycles, 212)
    }

    func testExternalPowerWithoutChargingIsHeld() throws {
        let battery = try XCTUnwrap(batteryState(properties: ["IsCharging": false]))

        XCTAssertEqual(battery.supply, .external)
    }

    func testOnBatteryTheEstimateIsTimeToEmptyAndAllOnesMeansUnknown() throws {
        let known = try XCTUnwrap(batteryState(properties: ["ExternalConnected": false, "TimeRemaining": 125]))
        let unknown = try XCTUnwrap(batteryState(properties: ["ExternalConnected": false, "TimeRemaining": 65535]))

        XCTAssertEqual(known.supply, .discharging(timeToEmpty: .seconds(125 * 60)))
        XCTAssertEqual(unknown.supply, .discharging(timeToEmpty: nil))
    }

    func testWithoutTelemetryTheDrawIsTheBatteryPowerOnlyWhileDischarging() throws {
        var properties = batteryProperties()
        properties["PowerTelemetryData"] = nil
        let external = try XCTUnwrap(BatteryState(properties: properties))
        properties["ExternalConnected"] = false
        let discharging = try XCTUnwrap(BatteryState(properties: properties))

        XCTAssertNil(external.draw)
        XCTAssertEqual(try XCTUnwrap(discharging.draw), 12, accuracy: 0.0001)
    }

    func testAFreshCellCapsHealthAndIntelCapacitiesSitAtTheTopLevel() throws {
        var properties = batteryProperties()
        properties["BatteryData"] = ["CycleCount": 212]
        properties["AppleRawMaxCapacity"] = 6_311
        properties["DesignCapacity"] = 6_249
        let battery = try XCTUnwrap(BatteryState(properties: properties))

        XCTAssertEqual(battery.health, 1)
    }

    func testAnEntryWithoutCapacitiesIsNoBattery() {
        XCTAssertNil(BatteryState(properties: ["CurrentCapacity": 80, "MaxCapacity": 100]))
        XCTAssertNil(BatteryState(properties: [:]))
    }
}
