import Foundation
import Testing

@testable import Koogo

struct TodoTests {
  @Test
  func `todo text trims nonempty input and rejects whitespace`() throws {
    #expect(TodoText(" \n\t ") == nil)

    let text = try #require(TodoText("  write tests\n"))
    #expect(text.value == "write tests")
  }

  @Test
  func `todo property list keeps the flat schema`() throws {
    let todo = Todo(text: try #require(TodoText("ship it")), priority: .urgent)
    let data = try PropertyListEncoder().encode([todo])
    let propertyList = try #require(
      PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [[String: Any]]
    )

    #expect(propertyList[0]["text"] as? String == "ship it")
    #expect(propertyList[0]["priority"] as? String == "urgent")
  }
}
