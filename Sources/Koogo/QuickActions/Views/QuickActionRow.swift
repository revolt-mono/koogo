import SwiftUI

struct QuickActionCopy {
  let title: String
  let detail: String
}

struct QuickActionRow<Targets: Sendable>: View {
  let model: QuickActionModel<Targets>
  let systemImage: String
  let copy: (QuickActionModel<Targets>.Phase) -> QuickActionCopy

  var body: some View {
    let phase = model.phase
    let words = copy(phase)
    let activate = model.activate
    let isEnabled = activate != nil

    Button {
      activate?()
    } label: {
      HStack(spacing: 8) {
        Group {
          switch phase {
          case .unscanned,
               .scanning,
               .performing:
            ProgressView()
              .controlSize(.small)

          case .empty,
               .ready,
               .scanFailed,
               .performFailed:
            Image(systemName: systemImage)
          }
        }
        .frame(width: 22, height: 22)
        .foregroundStyle(.secondary)
        .background(.panelRaised, in: .rect(cornerRadius: 5))

        VStack(alignment: .leading, spacing: 2) {
          Text(words.title)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)

          Text(words.detail)
            .foregroundStyle(.secondary)
            .lineLimit(3)
        }

        Spacer(minLength: 0)
      }
      .padding(8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(.rect)
      .background(
        isHovered && isEnabled ? Color.white.opacity(0.1) : .panelCard,
        in: .rect(cornerRadius: 8),
      )
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled)
    .opacity(isEnabled ? 1 : 0.58)
    .onPointerHover { isHovered = $0 }
    .onAppear(perform: model.refresh)
    .onDisappear(perform: model.cancel)
  }

  @State private var isHovered = false
}
