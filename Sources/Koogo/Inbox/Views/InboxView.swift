import SwiftUI

struct InboxView: View {
    @Environment(InboxModel.self) private var inboxModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TodoEditor { inboxModel.add($0, priority: $1) }

            HStack(spacing: 8) {
                Text(inboxOpenSummary(inboxModel.todos))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Clear done", systemImage: "trash") {
                    inboxModel.clearCompleted()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .tint(.red)
                .disabled(!inboxModel.todos.contains(where: \.isCompleted))
            }
            .font(.system(size: 10, weight: .medium))

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(inboxModel.todos) { todo in
                        if todo.id != inboxModel.todos.first?.id {
                            DashedDivider()
                        }
                        TodoRow(todo: todo)
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

func inboxOpenSummary(_ todos: [Todo]) -> String {
    let open = todos.filter { !$0.isCompleted }
    let counts = TodoPriority.allCases.reversed().compactMap { priority in
        let count = open.count { $0.priority == priority }
        return count > 0 ? "\(count) \(priority.title)" : nil
    }
    return counts.isEmpty ? "no open todos" : counts.joined(separator: ", ")
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
    let todo: Todo

    @Environment(InboxModel.self) private var inboxModel
    @State private var isEditing = false

    var body: some View {
        Group {
            if isEditing {
                TodoInlineEditor(text: todo.text, onFinish: finishEditing)
            } else {
                HStack(alignment: .center, spacing: 8) {
                    Button {
                        inboxModel.update(todo.id) { $0.isCompleted.toggle() }
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

            Picker(
                "Priority",
                selection: Binding(
                    get: { todo.priority },
                    set: { new in inboxModel.update(todo.id) { $0.priority = new } }
                )
            ) {
                ForEach(TodoPriority.allCases, id: \.self) { priority in
                    Text(priority.title)
                        .tag(priority)
                }
            }
            .pickerStyle(.menu)

            Button("Delete", role: .destructive) {
                inboxModel.delete(todo.id)
            }
        }
    }

    private func finishEditing(_ result: TodoInlineEditor.Result) {
        switch result {
        case .discarded:
            break
        case .saved(let text):
            inboxModel.update(todo.id) { $0.text = text }
        }
        isEditing = false
    }
}
