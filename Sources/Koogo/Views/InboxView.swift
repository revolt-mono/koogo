import Foundation
import SwiftUI

struct InboxView: View {
    private static let defaultsKey = "inbox-todo-items"

    private let dismissInput: () -> Void

    @State private var todos: [Todo]

    init(dismissInput: @escaping () -> Void) {
        self.dismissInput = dismissInput
        _todos = State(initialValue: Self.loadTodos())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TodoEditor {
                todos.insert($0, at: 0)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach($todos) { $todo in
                        TodoRow(todo: $todo)
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    todos.removeAll { $0.id == todo.id }
                                    dismissInput()
                                }
                            }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.automatic)
            .contentShape(.rect)
            .simultaneousGesture(
                TapGesture().onEnded {
                    dismissInput()
                }
            )
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 32)
        .frame(maxHeight: .infinity, alignment: .top)
        .onChange(of: todos, persistTodos)
    }

    private func persistTodos() {
        guard let data = try? PropertyListEncoder().encode(todos) else {
            return
        }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private static func loadTodos() -> [Todo] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
            let todos = try? PropertyListDecoder().decode([Todo].self, from: data)
        else {
            return []
        }
        return todos
    }
}

private struct TodoRow: View {
    @Binding var todo: Todo

    var body: some View {
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

            Image(systemName: "circle.dashed")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(todo.priority.color)
                .frame(width: 14, height: 18)
                .accessibilityLabel("\(todo.priority.rawValue) priority")

            Text(todo.text.value)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                .strikethrough(todo.isCompleted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(
            Color.white.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }
}
