import Foundation

/// One user-confirmed reset. A retry reuses the same credit and key so the server can dedupe it.
struct CodexQuotaResetAttempt: Equatable, Sendable {
    let credit: CodexQuotaSnapshot.ResetCredit
    let idempotencyKey = UUID()
}

enum CodexQuotaResetOutcome: String, Decodable, Equatable, Sendable {
    case reset
    case alreadyRedeemed
    case nothingToReset
    case noCredit
}

/// How a consume request ended; the phase decides whether the attempt can be dropped or must be retried.
enum CodexQuotaResetResult: Equatable, Sendable {
    case completed(CodexQuotaResetOutcome)
    /// Nothing reached the server; the attempt can be confirmed again or cancelled.
    case rejected(CodexAppServer.Failure)
    /// The request may have reached the server; only a retry with the same attempt can settle it.
    case unconfirmed(CodexAppServer.Failure)
}
