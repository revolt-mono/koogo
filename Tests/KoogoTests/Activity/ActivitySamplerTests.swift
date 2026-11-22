import Foundation
import Testing

@testable import Koogo

struct ActivitySamplerTests {
  // desktop macs have no battery, and a charging battery reports no draw.
  @Test
  func `the sampler reads this machine`() async throws {
    let sampler = ActivitySampler()

    let first = try await sampler.sample()
    let second = try await sampler.sample()

    for sample in [first, second] {
      #expect((0...1).contains(sample.cpu.total), "\(sample.cpu)")
      #expect(sample.memory.total == ProcessInfo.processInfo.physicalMemory)
      #expect(sample.memory.used <= sample.memory.total)
      #expect(sample.memory.wired > 0)
      #expect(!sample.processes.isEmpty)
    }
    if let gpu = second.gpu {
      #expect(!gpu.name.isEmpty)
      for stage in [gpu.utilization, gpu.renderer, gpu.tiler] {
        #expect((0...1).contains(stage))
      }
    }
    if let battery = second.battery {
      #expect((0...1).contains(battery.charge))
      #expect((0...1).contains(battery.health))
      if let draw = battery.draw {
        #expect(draw > 0)
      }
    }
  }
}
