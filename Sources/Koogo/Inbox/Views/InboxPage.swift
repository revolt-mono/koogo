import SwiftUI

struct InboxPage: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: PanelLayout.gap) {
        TodoComposer()

        InboxSummary()
      }
      .padding(.horizontal, PanelLayout.inset)

      TodoList()
    }
    .frame(maxHeight: .infinity, alignment: .top)
  }
}

private struct InboxSummary: View {
  var body: some View {
    HStack(spacing: 8) {
      Text(inboxModel.openSummary)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      Button("Clear done", systemImage: "trash") {
        inboxModel.clearCompleted()
      }
      .labelStyle(.iconOnly)
      .buttonStyle(.borderless)
      .foregroundStyle(inboxModel.hasCompleted ? Color.red : Color.secondary)
      .disabled(!inboxModel.hasCompleted)
    }
    .font(.system(size: 10, weight: .medium))
  }

  @Environment(InboxModel.self) private var inboxModel
}
