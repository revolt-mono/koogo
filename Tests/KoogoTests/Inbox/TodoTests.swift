import XCTest

@testable import Koogo

final class TodoTests: XCTestCase {
    func testTodoTextTrimsNonemptyInputAndRejectsWhitespace() throws {
        XCTAssertNil(TodoText(" \n\t "))

        let text = try XCTUnwrap(TodoText("  write tests\n"))
        XCTAssertEqual(text.value, "write tests")
    }

    func testTodoPropertyListKeepsTheFlatSchema() throws {
        let todo = Todo(text: try XCTUnwrap(TodoText("ship it")), priority: .urgent)
        let data = try PropertyListEncoder().encode([todo])
        let propertyList = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [[String: Any]]
        )

        XCTAssertEqual(propertyList[0]["text"] as? String, "ship it")
        XCTAssertEqual(propertyList[0]["priority"] as? String, "urgent")
    }
}
