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

/// The steps of spending one banked reset, with the rules for moving between them.
enum CodexQuotaResetFlow: Equatable {
    case idle
    case confirming(CodexQuotaResetAttempt, rejection: ToolFailure? = nil)
    case submitting(CodexQuotaResetAttempt, retryingUnconfirmed: Bool)
    case completed(CodexQuotaResetOutcome)
    /// The server may have received the request, so only the same attempt may be sent again.
    case unconfirmed(CodexQuotaResetAttempt, ToolFailure)

    var acceptsChoice: Bool {
        switch self {
        case .idle, .completed: true
        case .confirming, .submitting, .unconfirmed: false
        }
    }

    var submission: (attempt: CodexQuotaResetAttempt, retryingUnconfirmed: Bool)? {
        switch self {
        case .confirming(let attempt, _): (attempt, false)
        case .unconfirmed(let attempt, _): (attempt, true)
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

    /// Where a submission lands. A rejection while retrying stays unconfirmed, since the first request may still have landed.
    static func settled(
        _ attempt: CodexQuotaResetAttempt,
        retryingUnconfirmed: Bool,
        _ result: CodexQuotaResetResult
    ) -> Self {
        switch result {
        case .success(let outcome): .completed(outcome)
        case .failure(.unconfirmed(let failure)): .unconfirmed(attempt, failure)
        case .failure(.rejected(let failure)) where retryingUnconfirmed: .unconfirmed(attempt, failure)
        case .failure(.rejected(let failure)): .confirming(attempt, rejection: failure)
        }
    }
}
