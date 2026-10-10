import Observation

/// One metric over the recent samples, oldest first, as fractions of its scale.
struct ActivityTrend: Equatable {
    let values: [Double]
}

extension ActivityTrend {
    /// Readings without a natural ceiling scaled so the highest one reaches the top.
    init(scalingToPeak readings: [Double]) {
        let peak = readings.max() ?? 0
        self.init(values: peak > 0 ? readings.map { $0 / peak } : readings)
    }
}

/// As many samples as the widest chart shows. `monitor` is the only producer and runs exactly as long as the task the open panel holds.
@MainActor
@Observable
final class ActivityModel {
    nonisolated static let historyLength = 64

    private let interval: Duration
    private let sample: @Sendable () async throws -> ActivitySample

    private(set) var samples: [ActivitySample] = []

    var latest: ActivitySample? { samples.last }

    var cpuTrend: ActivityTrend { ActivityTrend(values: samples.map(\.cpu.total)) }

    var gpuTrend: ActivityTrend { ActivityTrend(values: samples.compactMap { $0.gpu?.utilization }) }

    var drawTrend: ActivityTrend { ActivityTrend(scalingToPeak: samples.compactMap { $0.battery?.draw }) }

    init(interval: Duration = .seconds(3), sample: @escaping @Sendable () async throws -> ActivitySample) {
        self.interval = interval
        self.sample = sample
    }

    /// Samples every interval until the task is cancelled. A failed sample logs and leaves the last one in place.
    func monitor() async {
        while !Task.isCancelled {
            do {
                samples.append(try await sample())
                samples.removeFirst(max(samples.count - Self.historyLength, 0))
            } catch {
                guard !Task.isCancelled else { return }
                Telemetry.activity.error("sample failed error=\(String(describing: error), privacy: .public)")
            }
            try? await Task.sleep(for: interval)
        }
    }
}
