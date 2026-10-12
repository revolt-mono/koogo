import SwiftUI

/// Samples while shown; leaving the page ends the task, so nothing runs in the background.
struct ActivityPage: View {
    @Environment(ActivityModel.self) private var activityModel

    let isShown: Bool

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
            }
            .panelPageScroll()
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .task(id: isShown) {
            guard isShown else { return }
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
            headline: Measure(fraction: load.total),
            details: [
                "User": Measure(fraction: load.user).text,
                "System": Measure(fraction: load.system).text,
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
            headline: Measure(fraction: load.utilization),
            details: [
                "Render": Measure(fraction: load.renderer).text,
                "Tile": Measure(fraction: load.tiler).text,
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
            subtitle: "\(Measure(bytes: usage.used).text) of \(Measure(bytes: usage.total).text)"
        ) {
            VStack(spacing: 12) {
                ActivityDetails(details: [
                    "App": Measure(bytes: usage.app).text,
                    "Wired": Measure(bytes: usage.wired).text,
                    "Compressed": Measure(bytes: usage.compressed).text,
                ])

                let share = Double(usage.used) / Double(usage.total)
                ProgressView(value: share)
                    .progressViewStyle(.panel)
                    .accessibilityLabel("Memory in use")
                    .accessibilityValue(Measure(fraction: share).text)
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
                    ActivityHeadline(measure: Measure(fraction: state.charge))

                    ActivityDetails(details: [
                        "Draw": state.draw.map { Measure(watts: $0).text } ?? "–",
                        "Health": Measure(fraction: state.health).text,
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
        case .charging(let timeToFull?): "charging · \(timeToFull.formatted(.hoursMinutes)) to full"
        case .charging(nil): "charging"
        case .external: "on power"
        case .discharging(let timeToEmpty?): "\(timeToEmpty.formatted(.hoursMinutes)) left"
        case .discharging(nil): "on battery"
        }
    }
}
