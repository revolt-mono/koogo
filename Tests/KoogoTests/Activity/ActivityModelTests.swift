import Testing

@testable import Koogo

@MainActor
struct ActivityModelTests {
  @Test
  func `monitor keeps only the newest samples`() async throws {
    let calls = Counter()
    let model = ActivityModel(interval: .milliseconds(1)) {
      calls.increment() <= 10 ? ActivitySample.stub(cpu: 1) : ActivitySample.stub(cpu: 0, gpu: nil, draw: nil)
    }

    let task = Task { await model.monitor() }
    defer { task.cancel() }

    try await Poll.until { calls.value > ActivityModel.historyLength + 10 }
    #expect(model.cpuTrend == Array(repeating: 0, count: ActivityModel.historyLength))
    #expect(model.gpuTrend == [])
    #expect(model.drawTrend == [])
  }

  @Test
  func `trends follow each metric and skip what a machine lacks`() async throws {
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

    #expect(model.cpuTrend == [0.2, 0.6, 0.4])
    #expect(model.gpuTrend == [0.9, 0.3])
    #expect(model.drawTrend == [0.25, 1])
  }

  @Test
  func `a failed sample leaves the last one and sampling goes on`() async throws {
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
    #expect(model.cpuTrend == [0.1, 0.3])
  }
}
