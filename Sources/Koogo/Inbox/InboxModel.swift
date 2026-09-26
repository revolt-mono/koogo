import Foundation
import Observation

@MainActor
@Observable
final class InboxModel {
    private static let defaultsKey = "inbox-todo-items"

    private let defaults: UserDefaults

    private(set) var todos: [Todo] {
        didSet {
            guard let data = try? PropertyListEncoder().encode(todos) else {
                return
            }
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        todos =
            defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? PropertyListDecoder().decode([Todo].self, from: $0) }
            ?? []
    }

    /// Puts a new open todo at the top of the list.
    func add(_ text: TodoText, priority: TodoPriority) {
        todos.insert(Todo(text: text, priority: priority), at: 0)
    }

    func delete(_ id: Todo.ID) {
        todos.removeAll { $0.id == id }
    }

    func clearCompleted() {
        todos.removeAll(where: \.isCompleted)
    }

    /// Applies `change` to the todo with `id`, or does nothing when that todo is gone.
    func update(_ id: Todo.ID, _ change: (inout Todo) -> Void) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else {
            return
        }
        change(&todos[index])
    }
}
