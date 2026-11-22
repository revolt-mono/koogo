import Foundation
import Testing

@testable import Koogo

struct CPULoadTests {
  @Test
  func `load is each share of the ticks elapsed`() {
    let load = CPULoad(
      from: CPUTicks(user: 1_000, system: 500, idle: 8_000),
      to: CPUTicks(user: 1_220, system: 590, idle: 8_690),
    )

    #expect(abs(load.user - 0.22) < 0.0001)
    #expect(abs(load.system - 0.09) < 0.0001)
    #expect(abs(load.total - 0.31) < 0.0001)
  }

  @Test
  func `wrapped counters still count forward`() {
    let load = CPULoad(
      from: CPUTicks(user: UInt32.max - 9, system: 0, idle: 0),
      to: CPUTicks(user: 40, system: 0, idle: 50),
    )

    #expect(abs(load.user - 0.5) < 0.0001)
  }

  @Test
  func `no elapsed ticks read as idle`() {
    let ticks = CPUTicks(user: 7, system: 7, idle: 7)

    let load = CPULoad(from: ticks, to: ticks)

    #expect(load.user == 0)
    #expect(load.system == 0)
  }

  @Test
  func `the running machine reports its cores`() throws {
    let count =
      switch try CPUCores.read() {
      case .uniform(let count): count
      case .hybrid(let performance, let efficiency): performance + efficiency
      }

    #expect(count > 0)
    #expect(count <= ProcessInfo.processInfo.processorCount)
  }
}
