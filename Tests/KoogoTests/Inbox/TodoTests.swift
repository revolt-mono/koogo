import Foundation
import XCTest

@testable import Koogo

final class TodoTests: XCTestCase {
    func testTodoTextTrimsNonemptyInputAndRejectsWhitespace() throws {
        XCTAssertNil(TodoText(" \n\t "))

        let text = try XCTUnwrap(TodoText("  write tests\n"))
        XCTAssertEqual(text.value, "write tests")
    }

    func testTodoPropertyListRoundTripKeepsTheFlatSchema() throws {
        let text = try XCTUnwrap(TodoText("ship it"))
        var todo = Todo(text: text, priority: .normal)
        todo.priority = .urgent
        let data = try PropertyListEncoder().encode([todo])
        let propertyList = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [[String: Any]]
        )

        XCTAssertEqual(propertyList[0]["text"] as? String, "ship it")
        XCTAssertEqual(propertyList[0]["priority"] as? String, "urgent")
        XCTAssertEqual(try PropertyListDecoder().decode([Todo].self, from: data), [todo])
    }

    func testTodoDecodingRejectsBlankText() throws {
        let text = try XCTUnwrap(TodoText("valid"))
        let data = try PropertyListEncoder().encode([Todo(text: text, priority: .normal)])
        var propertyList = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [[String: Any]]
        )
        propertyList[0]["text"] = " \n "
        let invalidData = try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .binary,
            options: 0
        )

        XCTAssertThrowsError(try PropertyListDecoder().decode([Todo].self, from: invalidData))
    }

    func testOpenSummaryListsUrgentThenNormalThenBacklog() throws {
        let todos = try [
            todo("later", .backlog),
            todo("soon", .normal),
            todo("now", .urgent),
            todo("also soon", .normal),
        ]

        XCTAssertEqual(inboxOpenSummary(todos), "1 urgent, 2 normal, 1 backlog")
    }

    func testOpenSummarySkipsCompletedTodosAndZeroCounts() throws {
        let todos = try [
            todo("shipped", .urgent, isCompleted: true),
            todo("later", .backlog),
            todo("someday", .backlog),
        ]

        XCTAssertEqual(inboxOpenSummary(todos), "2 backlog")
    }

    func testOpenSummaryOfAnEmptyListSaysNoOpenTodos() {
        XCTAssertEqual(inboxOpenSummary([]), "no open todos")
    }

    private func todo(_ text: String, _ priority: TodoPriority, isCompleted: Bool = false) throws -> Todo {
        var todo = Todo(text: try XCTUnwrap(TodoText(text)), priority: priority)
        todo.isCompleted = isCompleted
        return todo
    }
}
