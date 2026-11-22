import Foundation

struct CodexQuotaResetAttempt: Equatable, Sendable {
  let credit: QuotaSnapshot.ResetCredit
  let idempotencyKey = UUID()
}

enum CodexQuotaResetOutcome: String, Decodable, Sendable {
  case reset
  case alreadyRedeemed
  case nothingToReset
  case noCredit
}

typealias CodexQuotaResetResult = Result<CodexQuotaResetOutcome, CodexAppServer.CallError>

protocol CodexQuotaResetSource: QuotaSource {
  func consume(_ attempt: CodexQuotaResetAttempt) async -> CodexQuotaResetResult
}

enum CodexQuotaResetFlow: Equatable {
  case idle
  case confirming(CodexQuotaResetAttempt, rejection: ToolFailure? = nil)
  case submitting
  case completed(CodexQuotaResetOutcome)
  case unconfirmed(CodexQuotaResetAttempt, ToolFailure)

  enum Submission {
    case first(CodexQuotaResetAttempt)
    case retry(CodexQuotaResetAttempt)

    var attempt: CodexQuotaResetAttempt {
      switch self {
      case .first(let attempt),
           .retry(let attempt): attempt
      }
    }

    func settled(by result: CodexQuotaResetResult) -> CodexQuotaResetFlow {
      switch (result, self) {
      case (.success(let outcome), _): .completed(outcome)
      case (.failure(.unconfirmed(let failure)), _),
           (.failure(.rejected(let failure)), .retry): .unconfirmed(attempt, failure)
      case (.failure(.rejected(let failure)), .first): .confirming(attempt, rejection: failure)
      }
    }
  }

  var acceptsChoice: Bool {
    switch self {
    case .idle,
         .completed: true
    case .confirming,
         .submitting,
         .unconfirmed: false
    }
  }

  var submission: Submission? {
    switch self {
    case .confirming(let attempt, _): .first(attempt)
    case .unconfirmed(let attempt, _): .retry(attempt)
    case .idle,
         .submitting,
         .completed: nil
    }
  }
}
