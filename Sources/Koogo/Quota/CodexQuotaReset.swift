import Foundation
import Synchronization

/// One user-confirmed reset. A retry reuses the same credit and key so the server can dedupe it.
final class CodexQuotaResetAttempt: Equatable, Sendable {
    let credit: CodexQuotaSnapshot.ResetCredit
    let idempotencyKey = UUID()
    /// Set before the request is written: a failed write can still have reached the server.
    let writeStarted = Mutex(false)

    init(credit: CodexQuotaSnapshot.ResetCredit) {
        self.credit = credit
    }

    static func == (lhs: CodexQuotaResetAttempt, rhs: CodexQuotaResetAttempt) -> Bool {
        lhs === rhs
    }
}

enum CodexQuotaResetOutcome: String, Decodable, Equatable, Sendable {
    case reset
    case alreadyRedeemed
    case nothingToReset
    case noCredit
}

enum CodexQuotaResetFailure: Error, Equatable, Sendable {
    case unavailable(CodexQuotaUnavailability)
    case rpc(code: Int)
}

struct CodexQuotaRPCError: Decodable, Error, Sendable {
    let code: Int
}
