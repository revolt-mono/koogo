import Foundation

/// Why no quota is shown; surfaced in telemetry and the `--report` output.
enum CodexQuotaUnavailability: String, Error, Encodable, Sendable {
    case binaryNotFound
    case timedOut
    case sessionFailed
    case emptyLimits
}

struct CodexQuotaService: Sendable {
    private let appServer: CodexAppServer

    init(
        executableCandidates: [URL] = CodexAppServer.standardCandidates(),
        timeout: Duration = .seconds(15)
    ) {
        appServer = CodexAppServer(executableCandidates: executableCandidates, timeout: timeout)
    }

    @concurrent
    func fetch() async -> Result<CodexQuotaSnapshot, CodexQuotaUnavailability> {
        let result: Result<CodexQuotaSnapshot, CodexQuotaUnavailability>
        do {
            let response: CodexQuotaResponse = try await appServer.call("account/rateLimits/read")
            result = response.snapshot.map(Result.success) ?? .failure(.emptyLimits)
        } catch {
            result =
                switch error.failure {
                case .binaryNotFound: .failure(.binaryNotFound)
                case .timedOut: .failure(.timedOut)
                case .sessionFailed, .methodNotFound, .rpc: .failure(.sessionFailed)
                }
        }

        switch result {
        case .success:
            Telemetry.quota.info("codex fetch available")
        case .failure(let reason):
            Telemetry.quota.info("codex fetch unavailable reason=\(reason.rawValue, privacy: .public)")
        }
        return result
    }

    @concurrent
    func consume(_ attempt: CodexQuotaResetAttempt) async -> CodexQuotaResetResult {
        let result: CodexQuotaResetResult
        do {
            let response: ConsumeResponse = try await appServer.call(
                "account/rateLimitResetCredit/consume",
                params: ConsumeParams(creditId: attempt.credit.id, idempotencyKey: attempt.idempotencyKey.uuidString)
            )
            result = .completed(response.outcome)
        } catch {
            result = error.requestMayHaveArrived ? .unconfirmed(error.failure) : .rejected(error.failure)
        }

        switch result {
        case .completed(let outcome):
            Telemetry.quota.info("codex reset outcome=\(outcome.rawValue, privacy: .public)")
        case .rejected, .unconfirmed:
            Telemetry.quota.error("codex reset failed \(String(describing: result), privacy: .public)")
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
