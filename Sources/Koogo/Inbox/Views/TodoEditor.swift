import SwiftUI

struct TodoEditor: View {
    let onSubmit: (TodoText, TodoPriority) -> Void

    @State private var text = ""
    @State private var priority = TodoPriority.normal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TodoTextInput(text: $text, mode: .composing, onSubmit: submit)
                .frame(maxWidth: .infinity)
                .frame(height: TodoTextInput.maxHeight)
                .overlay(alignment: .topLeading) {
                    Text("Add a todo…")
                        .font(Font(TodoTextInput.font))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, TodoTextInput.textInset.width)
                        .padding(.vertical, TodoTextInput.textInset.height)
                        .opacity(text.isEmpty ? 1 : 0)
                        .allowsHitTesting(false)
                }

            HStack(spacing: 8) {
                TodoPrioritySelector(selection: $priority)

                Spacer(minLength: 8)

                TodoSubmitButton(systemImage: "arrow.up", action: submit)
                    .disabled(todoText == nil)
                    .accessibilityLabel("Add todo")
            }
        }
        .padding(12)
        .background(.panelRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onMouseDownOutside { $0.window?.makeFirstResponder(nil) }
    }

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
    enum Result {
        case discarded
        case saved(TodoText)
    }

    let onFinish: (Result) -> Void

    @State private var draft: String

    init(text: TodoText, onFinish: @escaping (Result) -> Void) {
        self.onFinish = onFinish
        _draft = State(initialValue: text.value)
    }

    var body: some View {
        HStack(spacing: 8) {
            TodoTextInput(
                text: $draft,
                mode: .editing,
                onSubmit: submit,
                onCancel: { onFinish(.discarded) }
            )
            .frame(maxWidth: .infinity)

            TodoSubmitButton(systemImage: "checkmark", action: submit)
                .disabled(todoText == nil)
                .accessibilityLabel("Save todo")
        }
        .padding(8)
        .background(.panelRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        // Deciding on mouse down keeps a click on the save button from racing the discard.
        .onMouseDownOutside { _ in onFinish(.discarded) }
    }

    private var todoText: TodoText? {
        TodoText(draft)
    }

    private func submit() {
        guard let todoText else {
            return
        }
        onFinish(.saved(todoText))
    }
}

private struct TodoSubmitButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 8, weight: .bold))
                .frame(width: 12, height: 16)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
    }
}
