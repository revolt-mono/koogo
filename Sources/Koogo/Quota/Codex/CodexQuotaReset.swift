import Foundation

/// One user-confirmed reset. A retry reuses the same credit and key so the server can dedupe it.
struct CodexQuotaResetAttempt: Equatable, Sendable {
    let credit: CodexQuotaSnapshot.ResetCredit
    let idempotencyKey = UUID()
}

enum CodexQuotaResetOutcome: String, Decodable, Sendable {
    case reset
    case alreadyRedeemed
    case nothingToReset
    case noCredit
}

typealias CodexQuotaResetResult = Result<CodexQuotaResetOutcome, CodexAppServer.CallError>
