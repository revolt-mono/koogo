import Foundation

/// One user-confirmed reset. A retry reuses the same credit and key so the server can dedupe it.
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

/// A Codex tool that can also spend a banked reset.
protocol CodexQuotaResetSource: QuotaSource {
    func consume(_ attempt: CodexQuotaResetAttempt) async -> CodexQuotaResetResult
}

/// One send of an attempt. A retry follows an unconfirmed send, which may already have landed.
enum CodexQuotaResetSubmission: Equatable {
    case first(CodexQuotaResetAttempt)
    case retry(CodexQuotaResetAttempt)

    var attempt: CodexQuotaResetAttempt {
        switch self {
        case .first(let attempt), .retry(let attempt): attempt
        }
    }
}

/// The steps of spending one banked reset, with the rules for moving between them.
enum CodexQuotaResetFlow: Equatable {
    case idle
    case confirming(CodexQuotaResetAttempt, rejection: ToolFailure? = nil)
    case submitting(CodexQuotaResetSubmission)
    case completed(CodexQuotaResetOutcome)
    /// The server may have received the request, so only the same attempt may be sent again.
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

    /// A confirmation lives only while its credit is usable.
    func reconciled(usable: (QuotaSnapshot.ResetCredit) -> Bool) -> Self {
        if case .confirming(let attempt, _) = self, !usable(attempt.credit) {
            return .idle
        }
        return self
    }

    /// Where a submission lands. A rejected retry stays unconfirmed, since the first send may still have landed.
    static func settled(_ submission: CodexQuotaResetSubmission, _ result: CodexQuotaResetResult) -> Self {
        switch (result, submission) {
        case (.success(let outcome), _): .completed(outcome)
        case (.failure(.unconfirmed(let failure)), _): .unconfirmed(submission.attempt, failure)
        case (.failure(.rejected(let failure)), .retry(let attempt)): .unconfirmed(attempt, failure)
        case (.failure(.rejected(let failure)), .first(let attempt)): .confirming(attempt, rejection: failure)
        }
    }
}
