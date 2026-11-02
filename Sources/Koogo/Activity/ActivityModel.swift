import Observation
import os

/// app-scoped history; the visible page's task starts monitoring and owns the sampling lifetime.
@MainActor
@Observable
final class ActivityModel {
    /// one sample's charted metrics; a metric the machine lacks is nil and skipped in its trend.
    private struct Reading {
        let cpu: Double
        let gpu: Double?
        /// battery draw in watts.
        let draw: Double?
    }

    static let historyLength = 64

    private let interval: Duration
    private let sample: @Sendable () async throws -> ActivitySample

    private(set) var latest: ActivitySample?
    /// the newest samples, oldest first.
    private var readings: [Reading] = []

    var cpuTrend: [Double] { readings.map(\.cpu) }

    var gpuTrend: [Double] { readings.compactMap(\.gpu) }

    /// battery draw as fractions of its recent peak.
    var drawTrend: [Double] {
        let draws = readings.compactMap(\.draw)
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
                let next = try await sample()
                latest = next
                readings.append(Reading(cpu: next.cpu.total, gpu: next.gpu?.utilization, draw: next.battery?.draw))
                readings.removeFirst(max(readings.count - Self.historyLength, 0))
            } catch {
                guard !Task.isCancelled else { return }
                Logger.activity.error("sample failed error=\(String(describing: error), privacy: .public)")
            }
            try? await Task.sleep(for: interval)
        }
    }
}
