import Foundation
import XCTest

@testable import Koogo

@MainActor
final class InboxModelTests: XCTestCase {
    func testAddPutsTheNewestTodoFirstWithItsPriority() throws {
        let model = InboxModel(defaults: try makeIsolatedDefaults())

        model.add(try todoText("older"), priority: .backlog)
        model.add(try todoText("newer"), priority: .urgent)

        XCTAssertEqual(model.todos.map(\.text.value), ["newer", "older"])
        XCTAssertEqual(model.todos.map(\.priority), [.urgent, .backlog])
        XCTAssertEqual(model.todos.map(\.isCompleted), [false, false])
    }

    func testClearCompletedKeepsOpenTodos() throws {
        let model = InboxModel(defaults: try makeIsolatedDefaults())
        model.add(try todoText("done"), priority: .normal)
        model.add(try todoText("open"), priority: .normal)
        let done = try XCTUnwrap(model.todos.last)
        model.toggleCompleted(done.id)

        model.clearCompleted()

        XCTAssertEqual(model.todos.map(\.text.value), ["open"])
    }

    func testDeleteRemovesOnlyTheGivenTodo() throws {
        let model = InboxModel(defaults: try makeIsolatedDefaults())
        model.add(try todoText("keep"), priority: .normal)
        model.add(try todoText("remove"), priority: .normal)

        model.delete(try XCTUnwrap(model.todos.first).id)

        XCTAssertEqual(model.todos.map(\.text.value), ["keep"])
    }

    func testIntentsChangeOneTodoAndIgnoreAMissingID() throws {
        let model = InboxModel(defaults: try makeIsolatedDefaults())
        model.add(try todoText("untouched"), priority: .normal)
        model.add(try todoText("target"), priority: .normal)
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
        model.add(try todoText("first"), priority: .normal)
        model.add(try todoText("second"), priority: .backlog)
        let first = try XCTUnwrap(model.todos.last)
        let updatedText = try todoText("updated")
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

    func testOneUndecodableTodoLeavesTheOthersInPlace() throws {
        let defaults = try makeIsolatedDefaults()
        let model = InboxModel(defaults: defaults)
        model.add(try todoText("keep"), priority: .normal)
        var items = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: try XCTUnwrap(defaults.data(forKey: "inbox-todo-items")),
                format: nil
            ) as? [[String: Any]]
        )
        var broken = items[0]
        broken["id"] = UUID().uuidString
        broken["text"] = ""
        items.append(broken)
        defaults.set(
            try PropertyListSerialization.data(fromPropertyList: items, format: .binary, options: 0),
            forKey: "inbox-todo-items"
        )

        XCTAssertEqual(InboxModel(defaults: defaults).todos, model.todos)
    }

    func testOpenSummaryListsUrgentThenNormalThenBacklog() throws {
        let model = InboxModel(defaults: try makeIsolatedDefaults())
        model.add(try todoText("later"), priority: .backlog)
        model.add(try todoText("soon"), priority: .normal)
        model.add(try todoText("now"), priority: .urgent)
        model.add(try todoText("also soon"), priority: .normal)

        XCTAssertEqual(model.openSummary, "1 urgent, 2 normal, 1 backlog")
    }

    func testOpenSummarySkipsCompletedTodosAndZeroCounts() throws {
        let model = InboxModel(defaults: try makeIsolatedDefaults())
        model.add(try todoText("shipped"), priority: .urgent)
        model.add(try todoText("later"), priority: .backlog)
        model.add(try todoText("someday"), priority: .backlog)
        model.toggleCompleted(try XCTUnwrap(model.todos.first { $0.priority == .urgent }).id)

        XCTAssertEqual(model.openSummary, "2 backlog")
    }

    func testOpenSummaryOfAnEmptyInboxSaysNoOpenTodos() throws {
        XCTAssertEqual(InboxModel(defaults: try makeIsolatedDefaults()).openSummary, "no open todos")
    }
}

private func todoText(_ value: String) throws -> TodoText {
    try XCTUnwrap(TodoText(value))
}
