import Foundation
import Testing

@testable import Koogo

@MainActor
struct InboxModelTests {
  @Test
  func `add puts the newest todo first with its priority`() throws {
    let model = InboxModel(defaults: try scratch.makeIsolatedDefaults())

    model.add(try todoText("older"), priority: .backlog)
    model.add(try todoText("newer"), priority: .urgent)

    #expect(model.todos.map(\.text.value) == ["newer", "older"])
    #expect(model.todos.map(\.priority) == [.urgent, .backlog])
    #expect(model.todos.map(\.isCompleted) == [false, false])
  }

  @Test
  func `clear completed keeps open todos`() throws {
    let model = InboxModel(defaults: try scratch.makeIsolatedDefaults())
    model.add(try todoText("done"), priority: .normal)
    model.add(try todoText("open"), priority: .normal)
    let done = try #require(model.todos.last)
    model.toggleCompleted(done.id)

    model.clearCompleted()

    #expect(model.todos.map(\.text.value) == ["open"])
  }

  @Test
  func `delete removes only the given todo`() throws {
    let model = InboxModel(defaults: try scratch.makeIsolatedDefaults())
    model.add(try todoText("keep"), priority: .normal)
    model.add(try todoText("remove"), priority: .normal)

    model.delete(try #require(model.todos.first).id)

    #expect(model.todos.map(\.text.value) == ["keep"])
  }

  @Test
  func `intents change one todo and ignore a missing id`() throws {
    let model = InboxModel(defaults: try scratch.makeIsolatedDefaults())
    model.add(try todoText("untouched"), priority: .normal)
    model.add(try todoText("target"), priority: .normal)
    let target = try #require(model.todos.first)
    let untouched = try #require(model.todos.last)

    model.setPriority(.urgent, of: target.id)
    model.setPriority(.backlog, of: UUID())

    #expect(model.todos.first?.priority == .urgent)
    #expect(model.todos.last == untouched)
  }

  @Test
  func `changes persist across model instances`() throws {
    let defaults = try scratch.makeIsolatedDefaults()
    let model = InboxModel(defaults: defaults)
    model.add(try todoText("first"), priority: .normal)
    model.add(try todoText("second"), priority: .backlog)
    let first = try #require(model.todos.last)
    let updatedText = try todoText("updated")
    model.toggleCompleted(first.id)
    model.setPriority(.urgent, of: first.id)
    model.setText(updatedText, of: first.id)
    model.delete(try #require(model.todos.first).id)

    #expect(InboxModel(defaults: defaults).todos == model.todos)
  }

  @Test
  func `undecodable persistence loads empty`() throws {
    let defaults = try scratch.makeIsolatedDefaults()
    InboxModel(defaults: defaults).add(try todoText("saved"), priority: .normal)
    defaults.set(Data("invalid".utf8), forKey: "inbox-todo-items")

    #expect(InboxModel(defaults: defaults).todos.isEmpty)
  }

  @Test
  func `a blank saved todo leaves the others in place`() throws {
    let defaults = try scratch.makeIsolatedDefaults()
    let model = InboxModel(defaults: defaults)
    model.add(try todoText("keep"), priority: .normal)
    let saved = try #require(defaults.data(forKey: "inbox-todo-items"))
    var items = try #require(PropertyListSerialization.propertyList(from: saved, format: nil) as? [[String: Any]])
    var broken = items[0]
    broken["id"] = UUID().uuidString
    broken["text"] = " \n "
    items.append(broken)
    defaults.set(
      try PropertyListSerialization.data(fromPropertyList: items, format: .binary, options: 0),
      forKey: "inbox-todo-items",
    )

    #expect(InboxModel(defaults: defaults).todos == model.todos)
  }

  @Test
  func `open summary lists urgent then normal then backlog`() throws {
    let model = InboxModel(defaults: try scratch.makeIsolatedDefaults())
    model.add(try todoText("later"), priority: .backlog)
    model.add(try todoText("soon"), priority: .normal)
    model.add(try todoText("now"), priority: .urgent)
    model.add(try todoText("also soon"), priority: .normal)

    #expect(model.openSummary == "1 urgent, 2 normal, 1 backlog")
  }

  @Test
  func `open summary skips completed todos and zero counts`() throws {
    let model = InboxModel(defaults: try scratch.makeIsolatedDefaults())
    model.add(try todoText("shipped"), priority: .urgent)
    model.add(try todoText("later"), priority: .backlog)
    model.add(try todoText("someday"), priority: .backlog)
    model.toggleCompleted(try #require(model.todos.first { $0.priority == .urgent }).id)

    #expect(model.openSummary == "2 backlog")
  }

  private let scratch = Scratch()

  private func todoText(_ value: String) throws -> TodoText {
    try #require(TodoText(value))
  }
}
