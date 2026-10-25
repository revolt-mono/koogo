import Foundation
import os

struct CodexQuotaSource: CodexQuotaResetSource {
    private let appServer: CodexAppServer

    init(
        executableCandidates: [URL] = CommandLineTool.candidates(
            named: "codex",
            preferring: [
                Provider.codex.home(under: FileManager.default.homeDirectoryForCurrentUser)
                    .appending(path: "packages/standalone/current/bin")
            ]
        ),
        timeout: Duration = CommandLineTool.defaultTimeout
    ) {
        appServer = CodexAppServer(tool: CommandLineTool(candidates: executableCandidates, timeout: timeout))
    }

    func load() async -> QuotaReading {
        do throws(CodexAppServer.CallError) {
            let response: CodexQuotaResponse = try await appServer.call("account/rateLimits/read")
            return QuotaReading(response.snapshot)
        } catch .unconfirmed(.rpc(code: -32600)) {
            // codex rejects quota requests locally unless signed in with a chatgpt account.
            return .unavailable(.noPlan)
        } catch {
            return .unavailable(QuotaUnavailability(error.failure))
        }
    }

    func consume(_ attempt: CodexQuotaResetAttempt) async -> CodexQuotaResetResult {
        do {
            let response: ConsumeResponse = try await appServer.call(
                "account/rateLimitResetCredit/consume",
                params: ConsumeParams(creditId: attempt.credit.id, idempotencyKey: attempt.idempotencyKey)
            )
            Logger.quota.info("codex reset outcome=\(response.outcome.rawValue, privacy: .public)")
            return .success(response.outcome)
        } catch .unconfirmed(.rpc(code: let code)) where [-32700, -32600, -32601, -32602].contains(code) {
            // json-rpc reserves these codes for requests refused before running, so no reset was spent.
            Logger.quota.error("codex reset refused code=\(code, privacy: .public)")
            return .failure(.rejected(.rpc(code: code)))
        } catch {
            Logger.quota.error("codex reset failed \(String(describing: error), privacy: .public)")
            return .failure(error)
        }
    }
}

private struct ConsumeParams: Encodable {
    let creditId: String
    let idempotencyKey: UUID
}

private struct ConsumeResponse: Decodable {
    let outcome: CodexQuotaResetOutcome
}
