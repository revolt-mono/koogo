import Foundation

struct CodexQuotaSource: CodexQuotaResetSource {
    private let appServer: CodexAppServer

    init(
        executableCandidates: [URL] = CommandLineTool.candidates(
            named: "codex",
            preferring: [
                FileManager.default.homeDirectoryForCurrentUser.appending(
                    path: ".codex/packages/standalone/current/bin"
                )
            ]
        ),
        timeout: Duration = .seconds(15)
    ) {
        appServer = CodexAppServer(tool: CommandLineTool(candidates: executableCandidates, timeout: timeout))
    }

    func load() async -> QuotaReading {
        await QuotaReading { () throws(ToolFailure) in
            do throws(CodexAppServer.CallError) {
                let response: CodexQuotaResponse = try await appServer.call("account/rateLimits/read")
                return response.snapshot
            } catch {
                throw error.failure
            }
        }
    }

    @concurrent
    func consume(_ attempt: CodexQuotaResetAttempt) async -> CodexQuotaResetResult {
        do {
            let response: ConsumeResponse = try await appServer.call(
                "account/rateLimitResetCredit/consume",
                params: ConsumeParams(creditId: attempt.credit.id, idempotencyKey: attempt.idempotencyKey.uuidString)
            )
            Telemetry.quota.info("codex reset outcome=\(response.outcome.rawValue, privacy: .public)")
            return .success(response.outcome)
        } catch {
            Telemetry.quota.error("codex reset failed \(String(describing: error), privacy: .public)")
            return .failure(error)
        }
    }
}

private struct ConsumeParams: Encodable {
    let creditId: String
    let idempotencyKey: String
}

private struct ConsumeResponse: Decodable {
    let outcome: CodexQuotaResetOutcome
}
