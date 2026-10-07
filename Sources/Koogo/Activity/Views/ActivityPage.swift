import SwiftUI

/// Samples while the panel is open; closing it ends the task, so nothing runs in the background.
struct ActivityPage: View {
    private static let inset: CGFloat = 20
    private static let edgeFade: CGFloat = 12

    @Environment(ActivityModel.self) private var activityModel

    var body: some View {
        PanelPageContent(activityModel.latest, loading: "Sampling…") { sample in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    MemoryMetric(usage: sample.memory, trend: activityModel.memoryTrend)

                    CPUMetric(load: sample.cpu, trend: activityModel.cpuTrend)

                    if let gpu = sample.gpu {
                        GPUMetric(load: gpu, trend: activityModel.gpuTrend)
                    }

                    AppProcessList(groups: sample.processes)
                }
                .padding(.horizontal, Self.inset)
            }
            .panelScroll(edgeFade: Self.edgeFade, bottomInset: 32, scrollerInset: Self.inset)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .task {
            await activityModel.monitor()
        }
    }
}

private struct MemoryMetric: View {
    let usage: MemoryUsage
    let trend: ActivityTrend

    var body: some View {
        ActivityMetricView(
            title: "Memory",
            subtitle: "\(ActivityFormatting.bytes(usage.total).text) total",
            headline: ActivityFormatting.bytes(usage.used),
            details: [
                "App": ActivityFormatting.bytes(usage.app).text,
                "Wired": ActivityFormatting.bytes(usage.wired).text,
                "Compressed": ActivityFormatting.bytes(usage.compressed).text,
            ],
            trend: trend
        )
    }
}

private struct CPUMetric: View {
    let load: CPULoad
    let trend: ActivityTrend

    var body: some View {
        ActivityMetricView(
            title: "CPU",
            subtitle: load.cores.efficiency > 0
                ? "\(load.cores.performance)P · \(load.cores.efficiency)E cores"
                : "\(load.cores.performance) cores",
            headline: ActivityFormatting.percent(load.total),
            details: [
                "User": ActivityFormatting.percent(load.user).text,
                "System": ActivityFormatting.percent(load.system).text,
                "Average": ActivityFormatting.percent(trend.average).text,
            ],
            trend: trend
        )
    }
}

private struct GPUMetric: View {
    let load: GPULoad
    let trend: ActivityTrend

    var body: some View {
        ActivityMetricView(
            title: "GPU",
            subtitle: load.name,
            headline: ActivityFormatting.percent(load.utilization),
            details: [
                "Memory": ActivityFormatting.bytes(load.memory).text,
                "Average": ActivityFormatting.percent(trend.average).text,
                "Peak": ActivityFormatting.percent(trend.peak).text,
            ],
            trend: trend
        )
    }
}
