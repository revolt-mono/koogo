import Observation
import os

/// app-scoped history; the visible page's task starts monitoring and owns the sampling lifetime.
@MainActor
@Observable
final class ActivityModel {
    static let historyLength = 64

    private let interval: Duration
    private let sample: @Sendable () async throws -> ActivitySample

    private(set) var samples: [ActivitySample] = []

    var latest: ActivitySample? { samples.last }

    var cpuTrend: [Double] { samples.map(\.cpu.total) }

    var gpuTrend: [Double] { samples.compactMap { $0.gpu?.utilization } }

    var drawTrend: [Double] {
        let draws = samples.compactMap { $0.battery?.draw }
        let peak = draws.max() ?? 0
        return peak > 0 ? draws.map { $0 / peak } : draws
    }

    init(interval: Duration = .seconds(3), sample: @escaping @Sendable () async throws -> ActivitySample) {
        self.interval = interval
        self.sample = sample
    }

    func monitor() async {
        while !Task.isCancelled {
            do {
                samples.append(try await sample())
                samples.removeFirst(max(samples.count - Self.historyLength, 0))
            } catch {
                guard !Task.isCancelled else { return }
                Logger.activity.error("sample failed error=\(String(describing: error), privacy: .public)")
            }
            try? await Task.sleep(for: interval)
        }
    }
}
