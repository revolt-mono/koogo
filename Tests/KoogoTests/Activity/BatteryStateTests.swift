import Testing

@testable import Koogo

struct BatteryStateTests {
  @Test
  func `a charging battery reads its charge estimate draw health and cycles`() throws {
    let battery = try #require(BatteryState.stub(draw: 14.3))

    #expect(battery.charge == 0.8)
    #expect(battery.supply == .charging(timeToFull: .seconds(80 * 60)))
    let draw = try #require(battery.draw)
    #expect(abs(draw - 14.3) < 0.0001)
    #expect(abs(battery.health - 0.98992) < 0.0001)
    #expect(battery.cycles == 212)
  }

  @Test
  func `external power without charging is held`() throws {
    let battery = try #require(BatteryState.stub(properties: ["IsCharging": false]))

    #expect(battery.supply == .external)
  }

  @Test
  func `on battery the estimate is time to empty and all ones means unknown`() throws {
    let known = try #require(BatteryState.stub(properties: ["ExternalConnected": false, "TimeRemaining": 125]))
    let unknown = try #require(BatteryState.stub(properties: ["ExternalConnected": false, "TimeRemaining": 65535]))

    #expect(known.supply == .discharging(timeToEmpty: .seconds(125 * 60)))
    #expect(unknown.supply == .discharging(timeToEmpty: nil))
  }

  @Test
  func `without telemetry the draw is the battery power only while discharging`() throws {
    var properties = BatteryState.stubProperties()
    properties["PowerTelemetryData"] = nil
    let external = try #require(BatteryState(properties: properties))
    properties["ExternalConnected"] = false
    let discharging = try #require(BatteryState(properties: properties))

    #expect(external.draw == nil)
    let draw = try #require(discharging.draw)
    #expect(abs(draw - 12) < 0.0001)
  }

  @Test
  func `a fresh cell caps health and intel capacities sit at the top level`() throws {
    var properties = BatteryState.stubProperties()
    properties["BatteryData"] = ["CycleCount": 212]
    properties["AppleRawMaxCapacity"] = 6_311
    properties["DesignCapacity"] = 6_249
    let battery = try #require(BatteryState(properties: properties))

    #expect(battery.health == 1)
  }

  @Test
  func `an entry without capacities is no battery`() {
    #expect(BatteryState(properties: ["CurrentCapacity": 80, "MaxCapacity": 100]) == nil)
    #expect(BatteryState(properties: [:]) == nil)
  }
}
