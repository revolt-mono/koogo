import Foundation
import XCTest

@testable import Koogo

@MainActor
final class InboxModelTests: XCTestCase {
    func testAddPutsTheNewestTodoFirstWithItsPriority() throws {
        let model = InboxModel(defaults: try makeIsolatedDefaults())

        model.add(try XCTUnwrap(TodoText("older")), priority: .backlog)
        model.add(try XCTUnwrap(TodoText("newer")), priority: .urgent)

        XCTAssertEqual(model.todos.map(\.text.value), ["newer", "older"])
        XCTAssertEqual(model.todos.map(\.priority), [.urgent, .backlog])
        XCTAssertEqual(model.todos.map(\.isCompleted), [false, false])
    }

    func testClearCompletedKeepsOpenTodos() throws {
        let model = InboxModel(defaults: try makeIsolatedDefaults())
        model.add(try XCTUnwrap(TodoText("done")), priority: .normal)
        model.add(try XCTUnwrap(TodoText("open")), priority: .normal)
        let done = try XCTUnwrap(model.todos.last)
        model.update(done.id) { $0.isCompleted = true }

        model.clearCompleted()

        XCTAssertEqual(model.todos.map(\.text.value), ["open"])
    }

    func testDeleteRemovesOnlyTheGivenTodo() throws {
        let model = InboxModel(defaults: try makeIsolatedDefaults())
        model.add(try XCTUnwrap(TodoText("keep")), priority: .normal)
        model.add(try XCTUnwrap(TodoText("remove")), priority: .normal)

        model.delete(try XCTUnwrap(model.todos.first).id)

        XCTAssertEqual(model.todos.map(\.text.value), ["keep"])
    }

    func testUpdateChangesOneTodoAndIgnoresAMissingID() throws {
        let model = InboxModel(defaults: try makeIsolatedDefaults())
        model.add(try XCTUnwrap(TodoText("untouched")), priority: .normal)
        model.add(try XCTUnwrap(TodoText("target")), priority: .normal)
        let target = try XCTUnwrap(model.todos.first)
        let untouched = try XCTUnwrap(model.todos.last)

        model.update(target.id) { $0.priority = .urgent }
        model.update(UUID()) { $0.priority = .backlog }

        XCTAssertEqual(model.todos.first?.priority, .urgent)
        XCTAssertEqual(model.todos.last, untouched)
        XCTAssertEqual(model.todos.count, 2)
    }

    func testChangesPersistAcrossModelInstances() throws {
        let defaults = try makeIsolatedDefaults()
        let model = InboxModel(defaults: defaults)
        model.add(try XCTUnwrap(TodoText("first")), priority: .normal)
        model.add(try XCTUnwrap(TodoText("second")), priority: .backlog)
        let first = try XCTUnwrap(model.todos.last)
        let updatedText = try XCTUnwrap(TodoText("updated"))
        model.update(first.id) {
            $0.isCompleted = true
            $0.priority = .urgent
            $0.text = updatedText
        }
        model.delete(try XCTUnwrap(model.todos.first).id)

        XCTAssertEqual(InboxModel(defaults: defaults).todos, model.todos)
    }

    func testUndecodablePersistenceLoadsEmpty() throws {
        let defaults = try makeIsolatedDefaults()
        defaults.set(Data("invalid".utf8), forKey: "inbox-todo-items")

        XCTAssertTrue(InboxModel(defaults: defaults).todos.isEmpty)
    }
}
