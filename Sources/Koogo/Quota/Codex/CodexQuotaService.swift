import Foundation

struct CodexQuotaService: QuotaService {
    static let name = "codex"

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

    func load() async -> Result<CodexQuotaSnapshot, CLIQuotaUnavailability> {
        do {
            let response: CodexQuotaResponse = try await appServer.call("account/rateLimits/read")
            return response.snapshot.map(Result.success) ?? .failure(.emptyLimits)
        } catch {
            return switch error.failure {
            case .binaryNotFound: .failure(.binaryNotFound)
            case .timedOut: .failure(.timedOut)
            case .sessionFailed, .methodNotFound, .rpc: .failure(.sessionFailed)
            }
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
