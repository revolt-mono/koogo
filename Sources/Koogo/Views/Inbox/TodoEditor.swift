import SwiftUI

struct TodoEditor: View {
    let onSubmit: (Todo) -> Void

    @State private var draft = TodoDraft()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TodoTextInput(text: $draft.text, mode: .composing, onSubmit: submit)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .overlay(alignment: .topLeading) {
                    Text("Add a todo…")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 6)
                        .opacity(draft.text.isEmpty ? 1 : 0)
                        .allowsHitTesting(false)
                }

            HStack(spacing: 8) {
                TodoPrioritySelector(selection: $draft.priority)

                Spacer(minLength: 8)

                Button(action: submit) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .disabled(draft.todoText == nil)
                .accessibilityLabel("Add todo")
            }
        }
        .padding(12)
        .background(
            Color.white.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private func submit() {
        guard let text = draft.todoText else {
            return
        }
        onSubmit(Todo(text: text, priority: draft.priority))
        draft = TodoDraft()
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
                mode: .editing(onBlur: { onFinish(.discarded) }),
                onSubmit: submit
            )
            .frame(maxWidth: .infinity)
            .frame(height: 40)

            Button(action: submit) {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .disabled(todoText == nil)
            .accessibilityLabel("Save todo")
        }
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

private struct TodoDraft {
    var text = ""
    var priority = TodoPriority.normal

    var todoText: TodoText? {
        TodoText(text)
    }
}
