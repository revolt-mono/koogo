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
                LazyVStack(spacing: 0) {
                    ForEach($inboxModel.todos) { $todo in
                        if todo.id != inboxModel.todos.first?.id {
                            DashedDivider()
                        }
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

private struct DashedDivider: View {
    var body: some View {
        HorizontalLine()
            .stroke(.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .frame(height: 1)
    }
}

private struct HorizontalLine: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
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
                        .contentShape(.rect)
                        .onTapGesture(count: 2) {
                            isEditing = true
                        }
                }
            }
        }
        .padding(.vertical, 10)
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
