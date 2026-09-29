import SwiftUI

/// The words a quick action row shows in one phase.
struct QuickActionCopy {
    let title: String
    let detail: String
}

/// One row of the quick actions popover: an icon or spinner, the phase's copy, and a click that
/// performs when ready or rescans after a failure.
struct QuickActionRow<Targets: Sendable>: View {
    let model: QuickActionModel<Targets>
    let systemImage: String
    let copy: (QuickActionModel<Targets>.Phase) -> QuickActionCopy

    @State private var isHovered = false

    var body: some View {
        let phase = model.phase
        let words = copy(phase)
        let click: (@MainActor () -> Void)? =
            switch phase {
            case .ready: model.perform
            case .failed: model.refresh
            case .scanning, .idle, .performing: nil
            }
        let isEnabled = click != nil

        Button {
            click?()
        } label: {
            HStack(spacing: 8) {
                Group {
                    switch phase {
                    case .scanning, .performing:
                        ProgressView()
                            .controlSize(.small)
                    case .failed:
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 11, weight: .medium))
                    case .idle, .ready:
                        Image(systemName: systemImage)
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .frame(width: 22, height: 22)
                .foregroundStyle(.secondary)
                .background(
                    Color.white.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(words.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(words.detail)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .background(
                Color.white.opacity(isHovered && isEnabled ? 0.1 : 0.06),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.58)
        .onHover { isHovered = $0 }
        .onAppear {
            // Only the first scan starts here; an action with nothing to scan for is already ready.
            if case .scanning = model.phase {
                model.refresh()
            }
        }
        .onDisappear(perform: model.cancel)
    }
}
