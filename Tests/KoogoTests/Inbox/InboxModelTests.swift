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
        model.toggleCompleted(done.id)

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

    func testIntentsChangeOneTodoAndIgnoreAMissingID() throws {
        let model = InboxModel(defaults: try makeIsolatedDefaults())
        model.add(try XCTUnwrap(TodoText("untouched")), priority: .normal)
        model.add(try XCTUnwrap(TodoText("target")), priority: .normal)
        let target = try XCTUnwrap(model.todos.first)
        let untouched = try XCTUnwrap(model.todos.last)

        model.setPriority(.urgent, of: target.id)
        model.setPriority(.backlog, of: UUID())

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
        model.toggleCompleted(first.id)
        model.setPriority(.urgent, of: first.id)
        model.setText(updatedText, of: first.id)
        model.delete(try XCTUnwrap(model.todos.first).id)

        XCTAssertEqual(InboxModel(defaults: defaults).todos, model.todos)
    }

    func testUndecodablePersistenceLoadsEmpty() throws {
        let defaults = try makeIsolatedDefaults()
        defaults.set(Data("invalid".utf8), forKey: "inbox-todo-items")

        XCTAssertTrue(InboxModel(defaults: defaults).todos.isEmpty)
    }

    func testOpenSummaryListsUrgentThenNormalThenBacklog() throws {
        let model = InboxModel(defaults: try makeIsolatedDefaults())
        model.add(try XCTUnwrap(TodoText("later")), priority: .backlog)
        model.add(try XCTUnwrap(TodoText("soon")), priority: .normal)
        model.add(try XCTUnwrap(TodoText("now")), priority: .urgent)
        model.add(try XCTUnwrap(TodoText("also soon")), priority: .normal)

        XCTAssertEqual(model.openSummary, "1 urgent, 2 normal, 1 backlog")
    }

    func testOpenSummarySkipsCompletedTodosAndZeroCounts() throws {
        let model = InboxModel(defaults: try makeIsolatedDefaults())
        model.add(try XCTUnwrap(TodoText("shipped")), priority: .urgent)
        model.add(try XCTUnwrap(TodoText("later")), priority: .backlog)
        model.add(try XCTUnwrap(TodoText("someday")), priority: .backlog)
        model.toggleCompleted(try XCTUnwrap(model.todos.first { $0.priority == .urgent }).id)

        XCTAssertEqual(model.openSummary, "2 backlog")
    }

    func testOpenSummaryOfAnEmptyInboxSaysNoOpenTodos() throws {
        XCTAssertEqual(InboxModel(defaults: try makeIsolatedDefaults()).openSummary, "no open todos")
    }
}
