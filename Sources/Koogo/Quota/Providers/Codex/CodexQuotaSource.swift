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
        do {
            let response: CodexQuotaResponse = try await appServer.call("account/rateLimits/read")
            return response.snapshot.map(QuotaReading.available) ?? .unavailable(.emptyLimits)
        } catch {
            return .unavailable(QuotaUnavailability(error.failure))
        }
    }

    @concurrent
    func consume(_ attempt: CodexQuotaResetAttempt) async -> CodexQuotaResetResult {
        let result: CodexQuotaResetResult
        do {
            let response: ConsumeResponse = try await appServer.call(
                "account/rateLimitResetCredit/consume",
                params: ConsumeParams(creditId: attempt.credit.id, idempotencyKey: attempt.idempotencyKey.uuidString)
            )
            result = .success(response.outcome)
        } catch {
            result = .failure(error)
        }

        switch result {
        case .success(let outcome):
            Telemetry.quota.info("codex reset outcome=\(outcome.rawValue, privacy: .public)")
        case .failure(let error):
            Telemetry.quota.error("codex reset failed \(String(describing: error), privacy: .public)")
        }
        return result
    }
}

private struct ConsumeParams: Encodable {
    let creditId: String
    let idempotencyKey: String
}

private struct ConsumeResponse: Decodable {
    let outcome: CodexQuotaResetOutcome
}
