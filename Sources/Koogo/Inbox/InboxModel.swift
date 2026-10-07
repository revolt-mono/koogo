import Foundation
import Observation

@MainActor
@Observable
final class InboxModel {
    private let storage: PersistedValue<[Todo]>

    private(set) var todos: [Todo] {
        didSet { storage.save(todos) }
    }

    var hasCompleted: Bool {
        todos.contains(where: \.isCompleted)
    }

    var openSummary: String {
        let open = todos.filter { !$0.isCompleted }
        let counts = TodoPriority.allCases.reversed().compactMap { priority in
            let count = open.count { $0.priority == priority }
            return count > 0 ? "\(count) \(priority.title)" : nil
        }
        return counts.isEmpty ? "no open todos" : counts.joined(separator: ", ")
    }

    init(defaults: UserDefaults = .standard) {
        storage = PersistedValue(key: "inbox-todo-items", defaults: defaults)
        todos = storage.load() ?? []
    }

    func add(_ text: TodoText, priority: TodoPriority) {
        todos.insert(Todo(text: text, priority: priority), at: 0)
    }

    func delete(_ id: Todo.ID) {
        todos.removeAll { $0.id == id }
    }

    func clearCompleted() {
        todos.removeAll(where: \.isCompleted)
    }

    func toggleCompleted(_ id: Todo.ID) {
        update(id) { $0.isCompleted.toggle() }
    }

    func setPriority(_ priority: TodoPriority, of id: Todo.ID) {
        update(id) { $0.priority = priority }
    }

    func setText(_ text: TodoText, of id: Todo.ID) {
        update(id) { $0.text = text }
    }

    private func update(_ id: Todo.ID, _ change: (inout Todo) -> Void) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else {
            return
        }
        change(&todos[index])
    }
}
