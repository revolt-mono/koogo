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

enum CodexQuotaResetFlow: Equatable {
    case idle
    case confirming(CodexQuotaResetAttempt, rejection: CodexAppServer.Failure? = nil)
    case submitting(CodexQuotaResetAttempt, retryingUnconfirmed: Bool)
    case completed(CodexQuotaResetOutcome)
    case unconfirmed(CodexQuotaResetAttempt, CodexAppServer.Failure)
}
