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

        try await waitUntil { calls.value > 70 }
        XCTAssertEqual(model.samples.count, ActivityModel.historyLength)
        let newest = try XCTUnwrap(model.latest).memory.used
        let oldest = try XCTUnwrap(model.samples.first).memory.used
        XCTAssertEqual(newest - oldest, 59)
    }

    func testTrendsFollowEachMetricAndSkipAMissingGPU() async throws {
        let calls = Counter()
        let model = ActivityModel(interval: .milliseconds(1)) {
            switch calls.increment() {
            case 1: activitySample(cpu: 0.2, memoryUsed: 16 << 30, gpu: 0.9)
            case 2: activitySample(cpu: 0.6, memoryUsed: 32 << 30, gpu: nil)
            case 3: activitySample(cpu: 0.4, memoryUsed: 48 << 30, gpu: 0.3)
            default: throw ActivityReadFailure.cpu
            }
        }

        let task = Task { await model.monitor() }
        try await waitUntil { model.samples.count == 3 }
        task.cancel()

        XCTAssertEqual(model.cpuTrend.average, 0.4, accuracy: 0.0001)
        XCTAssertEqual(model.cpuTrend.peak, 0.6, accuracy: 0.0001)
        XCTAssertEqual(model.memoryTrend.values, [0.25, 0.5, 0.75])
        XCTAssertEqual(model.gpuTrend.values, [0.9, 0.3])
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

    func testCancellingTheTaskStopsSampling() async throws {
        let calls = Counter()
        let model = ActivityModel(interval: .milliseconds(1)) {
            calls.increment()
            return activitySample()
        }

        let task = Task { await model.monitor() }
        try await waitUntil { model.latest != nil }
        task.cancel()
        await task.value

        let settled = calls.value
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(calls.value, settled)
    }
}
