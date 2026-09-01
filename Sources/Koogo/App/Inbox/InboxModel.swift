import Foundation
import Observation

@MainActor
@Observable
final class InboxModel {
    private static let defaultsKey = "inbox-todo-items"

    private let defaults: UserDefaults

    var todos: [Todo] {
        didSet {
            persist()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        todos =
            defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? PropertyListDecoder().decode([Todo].self, from: $0) }
            ?? []
    }

    private func persist() {
        guard let data = try? PropertyListEncoder().encode(todos) else {
            return
        }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
