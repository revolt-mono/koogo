import Foundation
import XCTest

@testable import Koogo

@MainActor
final class InboxModelTests: XCTestCase {
    func testMutationsPersistAcrossModelInstances() throws {
        let suiteName = "InboxModelTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let first = Todo(
            text: try XCTUnwrap(TodoText("first")),
            priority: .normal
        )
        let second = Todo(
            text: try XCTUnwrap(TodoText("second")),
            priority: .backlog
        )
        let model = InboxModel(defaults: defaults)

        model.todos.insert(first, at: 0)
        model.todos.insert(second, at: 0)
        let firstIndex = try XCTUnwrap(model.todos.firstIndex { $0.id == first.id })
        model.todos[firstIndex].isCompleted.toggle()
        model.todos[firstIndex].priority = .urgent
        model.todos[firstIndex].text = try XCTUnwrap(TodoText("updated"))
        model.todos.removeAll { $0.id == second.id }

        let restored = InboxModel(defaults: defaults)
        let todo = try XCTUnwrap(restored.todos.first)
        XCTAssertEqual(restored.todos.count, 1)
        XCTAssertEqual(todo.id, first.id)
        XCTAssertEqual(todo.text.value, "updated")
        XCTAssertEqual(todo.priority, .urgent)
        XCTAssertTrue(todo.isCompleted)
    }

    func testInvalidPersistenceLoadsAsEmpty() throws {
        let suiteName = "InboxModelTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set(Data("invalid".utf8), forKey: "inbox-todo-items")

        XCTAssertTrue(InboxModel(defaults: defaults).todos.isEmpty)
    }
}
