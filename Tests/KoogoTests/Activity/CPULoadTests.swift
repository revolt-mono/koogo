import Foundation
import XCTest

@testable import Koogo

final class CPULoadTests: XCTestCase {
    private let cores = CPUCores(performance: 8, efficiency: 4)

    func testLoadIsEachShareOfTheTicksElapsed() {
        let load = CPULoad(
            from: CPUTicks(user: 1_000, system: 500, idle: 8_000),
            to: CPUTicks(user: 1_220, system: 590, idle: 8_690),
            cores: cores
        )

        XCTAssertEqual(load.user, 0.22, accuracy: 0.0001)
        XCTAssertEqual(load.system, 0.09, accuracy: 0.0001)
        XCTAssertEqual(load.total, 0.31, accuracy: 0.0001)
    }

    func testWrappedCountersStillCountForward() {
        let load = CPULoad(
            from: CPUTicks(user: UInt32.max - 9, system: 0, idle: 0),
            to: CPUTicks(user: 40, system: 0, idle: 50),
            cores: cores
        )

        XCTAssertEqual(load.user, 0.5, accuracy: 0.0001)
    }

    func testNoElapsedTicksReadAsIdle() {
        let ticks = CPUTicks(user: 7, system: 7, idle: 7)

        let load = CPULoad(from: ticks, to: ticks, cores: cores)

        XCTAssertEqual(load.user, 0)
        XCTAssertEqual(load.system, 0)
    }

    func testTheRunningMachineReportsItsCores() throws {
        let cores = try CPUCores.read()

        XCTAssertGreaterThan(cores.performance, 0)
        XCTAssertLessThanOrEqual(cores.performance + cores.efficiency, ProcessInfo.processInfo.processorCount)
    }
}
