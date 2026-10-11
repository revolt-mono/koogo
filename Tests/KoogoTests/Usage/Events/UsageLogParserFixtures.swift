import Foundation

@testable import Koogo

func parse(_ line: String, with parser: inout some UsageLogParser) throws -> UsageLineOutcome? {
    try Data(line.utf8).withUnsafeBytes { try parser.parse($0) }
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
