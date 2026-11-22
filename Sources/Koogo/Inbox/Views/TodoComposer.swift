import SwiftUI

struct TodoComposer: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      TodoTextInput(text: $draft, mode: .composing, onSubmit: submit)
        .frame(maxWidth: .infinity)
        .frame(height: TodoTextInput.maxHeight)
        .overlay(alignment: .topLeading) {
          Text("Add a todo…")
            .font(Font(TodoTextInput.Mode.composing.font))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, TodoTextInput.Mode.composing.textInset.width)
            .padding(.vertical, TodoTextInput.Mode.composing.textInset.height)
            .opacity(draft.isEmpty ? 1 : 0)
            .allowsHitTesting(false)
        }

      HStack(spacing: 8) {
        TodoPrioritySelector(selection: $priority)

        Spacer(minLength: 8)

        Button(action: submit) {
          Image(systemName: "arrow.up")
            .font(.system(size: 8, weight: .bold))
            .frame(width: 12, height: 16)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .disabled(text == nil)
        .accessibilityLabel("Add todo")
      }
    }
    .panelCard()
    .onMouseDownOutside { $0.window?.makeFirstResponder(nil) }
  }

  @Environment(InboxModel.self) private var inboxModel
  @State private var draft = ""
  @State private var priority = TodoPriority.normal

  private var text: TodoText? {
    TodoText(draft)
  }

  private func submit() {
    guard let text else {
      return
    }
    inboxModel.add(text, priority: priority)
    draft = ""
    priority = .normal
  }
}
