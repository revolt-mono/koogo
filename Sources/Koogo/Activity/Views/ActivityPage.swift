import SwiftUI

/// Samples while the panel is open; closing it ends the task, so nothing runs in the background.
struct ActivityPage: View {
    @Environment(ActivityModel.self) private var activityModel

    var body: some View {
        PanelPageContent(activityModel.latest, loading: "Sampling…") { sample in
            ScrollView {
                VStack(alignment: .leading, spacing: PanelLayout.gap) {
                    HStack(alignment: .top, spacing: PanelLayout.gap) {
                        CPUSection(load: sample.cpu, trend: activityModel.cpuTrend)

                        if let gpu = sample.gpu {
                            GPUSection(load: gpu, trend: activityModel.gpuTrend)
                        }
                    }

                    MemorySection(usage: sample.memory)

                    if let battery = sample.battery {
                        BatterySection(state: battery, drawTrend: activityModel.drawTrend)
                    }

                    AppProcessList(groups: sample.processes, sampledAt: sample.taken)
                }
                .padding(.horizontal, PanelLayout.inset)
            }
            .panelPageScroll()
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .task {
            await activityModel.monitor()
        }
    }
}

private struct CPUSection: View {
    let load: CPULoad
    let trend: ActivityTrend

    var body: some View {
        ActivityLoadTile(
            title: "CPU",
            subtitle: load.cores.efficiency > 0
                ? "\(load.cores.performance)P · \(load.cores.efficiency)E"
                : "\(load.cores.performance) cores",
            headline: ActivityFormatting.percent(load.total),
            details: [
                "User": ActivityFormatting.percent(load.user).text,
                "System": ActivityFormatting.percent(load.system).text,
            ],
            trend: trend
        )
    }
}

private struct GPUSection: View {
    let load: GPULoad
    let trend: ActivityTrend

    var body: some View {
        ActivityLoadTile(
            title: "GPU",
            subtitle: load.name,
            headline: ActivityFormatting.percent(load.utilization),
            details: [
                "Render": ActivityFormatting.percent(load.renderer).text,
                "Tile": ActivityFormatting.percent(load.tiler).text,
            ],
            trend: trend
        )
    }
}

private struct MemorySection: View {
    let usage: MemoryUsage

    var body: some View {
        PanelSection(
            "Memory",
            subtitle: "\(ActivityFormatting.bytes(usage.used).text) of \(ActivityFormatting.bytes(usage.total).text)"
        ) {
            VStack(spacing: 12) {
                ActivityDetails(details: [
                    "App": ActivityFormatting.bytes(usage.app).text,
                    "Wired": ActivityFormatting.bytes(usage.wired).text,
                    "Compressed": ActivityFormatting.bytes(usage.compressed).text,
                ])

                let share = Double(usage.used) / Double(usage.total)
                ProgressView(value: share)
                    .progressViewStyle(.panel)
                    .accessibilityLabel("Memory in use")
                    .accessibilityValue(ActivityFormatting.percent(share).text)
            }
        }
    }
}

private struct BatterySection: View {
    let state: BatteryState
    let drawTrend: ActivityTrend

    var body: some View {
        PanelSection("Battery", subtitle: supply) {
            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    ActivityHeadline(measure: ActivityFormatting.percent(state.charge))

                    ActivityDetails(details: [
                        "Draw": state.draw.map { ActivityFormatting.watts($0).text } ?? "–",
                        "Health": ActivityFormatting.percent(state.health).text,
                        "Cycles": "\(state.cycles)",
                    ])
                }

                if !drawTrend.values.isEmpty {
                    ActivityTrendChart(trend: drawTrend)
                }
            }
        }
    }

    private var supply: String {
        switch state.supply {
        case .charging(let timeToFull?): "charging · \(ActivityFormatting.duration(timeToFull)) to full"
        case .charging(nil): "charging"
        case .external: "on power"
        case .discharging(let timeToEmpty?): "\(ActivityFormatting.duration(timeToEmpty)) left"
        case .discharging(nil): "on battery"
        }
    }
}
