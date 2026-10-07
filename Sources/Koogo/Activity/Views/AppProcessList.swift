import AppKit
import SwiftUI

struct AppProcessList: View {
    let groups: [AppProcessGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Processes")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)

            VStack(spacing: 8) {
                ForEach(groups) { group in
                    AppProcessRow(group: group)
                }
            }
            .padding(12)
            .background(
                Color.black.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
    }
}

private struct AppProcessRow: View {
    let group: AppProcessGroup

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: group.iconPath))
                .resizable()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .fontWeight(.semibold)

                Text("^[\(group.processCount) process](inflect: true)")
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                Text(ActivityFormatting.bytes(group.footprint).text)
                    .fontWeight(.semibold)

                let cpu = ActivityFormatting.percent(group.cpu).text
                let gpu = ActivityFormatting.percent(group.gpu).text
                Text("\(cpu) CPU, \(gpu) GPU")
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
        }
        .font(.system(size: 9, weight: .medium))
        .lineLimit(1)
    }
}
