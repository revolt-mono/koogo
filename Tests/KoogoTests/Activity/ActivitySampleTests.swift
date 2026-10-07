import Foundation
import XCTest

@testable import Koogo

final class ActivitySampleTests: XCTestCase {
    func testTheSamplerReadsThisMachine() async throws {
        let sampler = ActivitySampler()

        let first = try await sampler.sample()
        let second = try await sampler.sample()

        for sample in [first, second] {
            XCTAssertTrue((0...1).contains(sample.cpu.total), "\(sample.cpu)")
            XCTAssertEqual(sample.memory.total, ProcessInfo.processInfo.physicalMemory)
            XCTAssertLessThanOrEqual(sample.memory.used, sample.memory.total)
            XCTAssertGreaterThan(sample.memory.wired, 0)
            XCTAssertFalse(sample.processes.isEmpty)
        }
        if let gpu = second.gpu {
            XCTAssertFalse(gpu.name.isEmpty)
            XCTAssertTrue((0...1).contains(gpu.utilization))
        }
    }
}
