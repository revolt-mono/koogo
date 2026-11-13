import Foundation

enum TodoPriority: String, CaseIterable, Codable {
  case backlog
  case normal
  case urgent

  var title: String {
    rawValue
  }
}

struct TodoText: Codable, Equatable {
  init?(_ input: String) {
    let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else {
      return nil
    }
    self.value = value
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    guard let text = Self(try container.decode(String.self)) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Todo text must not be empty",
      )
    }
    self = text
  }

  let value: String

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(value)
  }
}

struct Todo: Codable, Equatable, Identifiable {
  init(text: TodoText, priority: TodoPriority) {
    id = UUID()
    self.text = text
    self.priority = priority
    isCompleted = false
  }

  let id: UUID
  var text: TodoText
  var priority: TodoPriority
  var isCompleted: Bool
}
