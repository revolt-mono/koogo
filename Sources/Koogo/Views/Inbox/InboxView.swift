import SwiftUI

struct InboxView: View {
    @Environment(InboxModel.self) private var inboxModel

    var body: some View {
        @Bindable var inboxModel = inboxModel

        VStack(alignment: .leading, spacing: 12) {
            TodoEditor {
                inboxModel.todos.insert($0, at: 0)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach($inboxModel.todos) { $todo in
                        TodoRow(todo: $todo) { [id = todo.id] in
                            inboxModel.todos.removeAll { $0.id == id }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.automatic)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 32)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct TodoRow: View {
    @Binding var todo: Todo
    let onDelete: () -> Void

    @State private var isEditing = false

    var body: some View {
        Group {
            if isEditing {
                TodoInlineEditor(text: todo.text, onFinish: finishEditing)
            } else {
                HStack(alignment: .center, spacing: 8) {
                    Button {
                        todo.isCompleted.toggle()
                    } label: {
                        Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 18, height: 18)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(todo.isCompleted ? Color.accentColor : Color.secondary)
                    .accessibilityLabel(todo.isCompleted ? "Mark incomplete" : "Mark complete")

                    Image(systemName: todo.priority.symbolName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(todo.priority.color)
                        .frame(width: 14, height: 18)
                        .accessibilityLabel("\(todo.priority.title) priority")

                    Text(todo.text.value)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                        .strikethrough(todo.isCompleted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(10)
        .background(
            Color.white.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .contextMenu {
            Button("Edit") {
                isEditing = true
            }

            Picker("Priority", selection: $todo.priority) {
                ForEach(TodoPriority.allCases, id: \.self) { priority in
                    Text(priority.title)
                        .tag(priority)
                }
            }
            .pickerStyle(.menu)

            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private func finishEditing(_ result: TodoInlineEditor.Result) {
        switch result {
        case .discarded:
            break
        case .saved(let text):
            todo.text = text
        }
        isEditing = false
    }
}
