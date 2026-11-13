import XCTest

@testable import Koogo

@MainActor
final class ActivityModelTests: XCTestCase {
  func testMonitorKeepsOnlyTheNewestSamples() async throws {
    let calls = Counter()
    let model = ActivityModel(interval: .milliseconds(1)) {
      calls.increment() <= 10 ? ActivitySample.stub(cpu: 1) : ActivitySample.stub(cpu: 0, gpu: nil, draw: nil)
    }

    let task = Task { await model.monitor() }
    defer { task.cancel() }

    try await Poll.until { calls.value > ActivityModel.historyLength + 10 }
    XCTAssertEqual(model.cpuTrend, Array(repeating: 0, count: ActivityModel.historyLength))
    XCTAssertEqual(model.gpuTrend, [])
    XCTAssertEqual(model.drawTrend, [])
  }

  func testTrendsFollowEachMetricAndSkipWhatAMachineLacks() async throws {
    let calls = Counter()
    let model = ActivityModel(interval: .milliseconds(1)) {
      switch calls.increment() {
      case 1: ActivitySample.stub(cpu: 0.2, gpu: 0.9, draw: 5)
      case 2: ActivitySample.stub(cpu: 0.6, gpu: nil, draw: 20)
      case 3: ActivitySample.stub(cpu: 0.4, gpu: 0.3, draw: nil)
      default: throw ActivityReadFailure.cpu
      }
    }

    let task = Task { await model.monitor() }
    try await Poll.until { model.cpuTrend.count == 3 }
    task.cancel()

    XCTAssertEqual(model.cpuTrend, [0.2, 0.6, 0.4])
    XCTAssertEqual(model.gpuTrend, [0.9, 0.3])
    XCTAssertEqual(model.drawTrend, [0.25, 1])
  }

  func testAFailedSampleLeavesTheLastOneAndSamplingGoesOn() async throws {
    let calls = Counter()
    let model = ActivityModel(interval: .milliseconds(1)) {
      switch calls.increment() {
      case 1: ActivitySample.stub(cpu: 0.1)
      case 3: ActivitySample.stub(cpu: 0.3)
      default: throw ActivityReadFailure.cpu
      }
    }

    let task = Task { await model.monitor() }
    defer { task.cancel() }

    try await Poll.until { model.cpuTrend.count == 2 }
    XCTAssertEqual(model.cpuTrend, [0.1, 0.3])
  }
}
