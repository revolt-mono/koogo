import Foundation

/// retries reuse the confirmed credit and idempotency key so the server can deduplicate the reset.
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

enum CodexQuotaResetSubmission: Equatable {
    case first(CodexQuotaResetAttempt)
    case retry(CodexQuotaResetAttempt)

    var attempt: CodexQuotaResetAttempt {
        switch self {
        case .first(let attempt), .retry(let attempt): attempt
        }
    }
}

enum CodexQuotaResetFlow: Equatable {
    case idle
    case confirming(CodexQuotaResetAttempt, rejection: ToolFailure? = nil)
    case submitting
    case completed(CodexQuotaResetOutcome)
    /// the server may have received the request; retries must reuse the same attempt.
    case unconfirmed(CodexQuotaResetAttempt, ToolFailure)

    var acceptsChoice: Bool {
        switch self {
        case .idle, .completed: true
        case .confirming, .submitting, .unconfirmed: false
        }
    }

    var submission: CodexQuotaResetSubmission? {
        switch self {
        case .confirming(let attempt, _): .first(attempt)
        case .unconfirmed(let attempt, _): .retry(attempt)
        case .idle, .submitting, .completed: nil
        }
    }

    static func settled(_ submission: CodexQuotaResetSubmission, _ result: CodexQuotaResetResult) -> Self {
        switch (result, submission) {
        case (.success(let outcome), _): .completed(outcome)
        case (.failure(.unconfirmed(let failure)), _): .unconfirmed(submission.attempt, failure)
        case (.failure(.rejected(let failure)), .retry(let attempt)): .unconfirmed(attempt, failure)
        case (.failure(.rejected(let failure)), .first(let attempt)): .confirming(attempt, rejection: failure)
        }
    }
}
