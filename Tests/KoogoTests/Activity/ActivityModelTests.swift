import XCTest

@testable import Koogo

@MainActor
final class ActivityModelTests: XCTestCase {
    func testMonitorKeepsOnlyTheNewestSamples() async throws {
        let calls = Counter()
        let model = ActivityModel(interval: .milliseconds(1)) {
            activitySample(memoryUsed: UInt64(calls.increment()))
        }

        let task = Task { await model.monitor() }
        defer { task.cancel() }

        try await waitUntil { calls.value > ActivityModel.historyLength + 10 }
        XCTAssertEqual(model.samples.count, ActivityModel.historyLength)
        let newest = try XCTUnwrap(model.latest).memory.used
        let oldest = try XCTUnwrap(model.samples.first).memory.used
        XCTAssertEqual(newest - oldest, UInt64(ActivityModel.historyLength - 1))
    }

    func testTrendsFollowEachMetricAndSkipWhatAMachineLacks() async throws {
        let calls = Counter()
        let model = ActivityModel(interval: .milliseconds(1)) {
            switch calls.increment() {
            case 1: activitySample(cpu: 0.2, gpu: 0.9, draw: 5)
            case 2: activitySample(cpu: 0.6, gpu: nil, draw: 20)
            case 3: activitySample(cpu: 0.4, gpu: 0.3, draw: nil)
            default: throw ActivityReadFailure.cpu
            }
        }

        let task = Task { await model.monitor() }
        try await waitUntil { model.samples.count == 3 }
        task.cancel()

        XCTAssertEqual(model.cpuTrend.values, [0.2, 0.6, 0.4])
        XCTAssertEqual(model.gpuTrend.values, [0.9, 0.3])
        XCTAssertEqual(model.drawTrend.values, [0.25, 1])
    }

    func testAFailedSampleLeavesTheLastOneAndSamplingGoesOn() async throws {
        let calls = Counter()
        let model = ActivityModel(interval: .milliseconds(1)) {
            switch calls.increment() {
            case 1: activitySample(cpu: 0.1)
            case 3: activitySample(cpu: 0.3)
            default: throw ActivityReadFailure.cpu
            }
        }

        let task = Task { await model.monitor() }
        defer { task.cancel() }

        try await waitUntil { model.samples.count == 2 }
        XCTAssertEqual(model.cpuTrend.values, [0.1, 0.3])
        XCTAssertGreaterThanOrEqual(calls.value, 3)
    }
}
