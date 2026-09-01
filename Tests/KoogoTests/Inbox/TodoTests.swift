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
}
