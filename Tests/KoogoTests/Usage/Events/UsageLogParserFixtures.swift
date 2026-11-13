import Foundation

@testable import Koogo

extension UsageLogParser {
  mutating func parse(_ line: String) throws -> UsageLineOutcome? {
    try Data(line.utf8).withUnsafeBytes { try parse($0) }
  }
}

extension UsageLineOutcome {
  var event: UsageEvent? {
    guard case .event(let event) = self else {
      return nil
    }
    return event
  }

  var unpricedModel: ModelID? {
    guard case .unpricedModel(let model, _) = self else {
      return nil
    }
    return model
  }
}
