import Observation

/// One metric over the recent samples, oldest first, as fractions of its capacity.
struct ActivityTrend: Equatable {
    let values: [Double]

    var average: Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }
    var peak: Double { values.max() ?? 0 }
}

/// The last three minutes of samples. `monitor` is the only producer and runs exactly as long as the task the open panel holds.
@MainActor
@Observable
final class ActivityModel {
    static let historyLength = 60

    private let interval: Duration
    private let sample: @Sendable () async throws -> ActivitySample

    private(set) var samples: [ActivitySample] = []

    var latest: ActivitySample? { samples.last }

    var cpuTrend: ActivityTrend { ActivityTrend(values: samples.map(\.cpu.total)) }

    var memoryTrend: ActivityTrend {
        ActivityTrend(values: samples.map { Double($0.memory.used) / Double($0.memory.total) })
    }

    var gpuTrend: ActivityTrend { ActivityTrend(values: samples.compactMap { $0.gpu?.utilization }) }

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
