import SwiftUI

struct TodoEditor: View {
  let onSubmit: (TodoText, TodoPriority) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      TodoTextInput(text: $text, mode: .composing, onSubmit: submit)
        .frame(maxWidth: .infinity)
        .frame(height: TodoTextInput.maxHeight)
        .overlay(alignment: .topLeading) {
          Text("Add a todo…")
            .font(Font(TodoTextInput.Mode.composing.font))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, TodoTextInput.Mode.composing.textInset.width)
            .padding(.vertical, TodoTextInput.Mode.composing.textInset.height)
            .opacity(text.isEmpty ? 1 : 0)
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
        .disabled(todoText == nil)
        .accessibilityLabel("Add todo")
      }
    }
    .panelCard()
    .onMouseDownOutside { $0.window?.makeFirstResponder(nil) }
  }

  @State private var text = ""
  @State private var priority = TodoPriority.normal

  private var todoText: TodoText? {
    TodoText(text)
  }

  private func submit() {
    guard let todoText else {
      return
    }
    onSubmit(todoText, priority)
    text = ""
    priority = .normal
  }
}

struct TodoInlineEditor: View {
  init(text: TodoText, onFinish: @escaping (TodoText?) -> Void) {
    self.onFinish = onFinish
    _draft = State(initialValue: text.value)
  }

  /// receives nil when the edit is discarded.
  let onFinish: (TodoText?) -> Void

  var body: some View {
    TodoTextInput(
      text: $draft,
      mode: .editing,
      onSubmit: submit,
      onCancel: { onFinish(nil) },
    )
    .frame(maxWidth: .infinity)
    // the field grows into the icon gap so the text itself stays where the label was.
    .padding(.horizontal, -TodoTextInput.Mode.editing.textInset.width)
    // textkit places the baseline half a point below where swiftui draws the same label.
    .offset(y: -0.5)
    .onMouseDownOutside { _ in onFinish(nil) }
  }

  @State private var draft: String

  private func submit() {
    if let text = TodoText(draft) {
      onFinish(text)
    }
  }
}

extension View {
  fileprivate func onMouseDownOutside(perform action: @escaping @MainActor (NSView) -> Void) -> some View {
    onLocalEvent([.leftMouseDown, .rightMouseDown]) { event, view in
      if !event.isInside(view) {
        action(view)
      }
      return event
    }
  }
}
