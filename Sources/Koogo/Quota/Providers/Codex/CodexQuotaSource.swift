import Foundation
import os

struct CodexQuotaSource: CodexQuotaResetSource {
  init(
    tool: CommandLineTool = CommandLineTool(
      named: "codex",
      preferring: [
        Provider.codex.home(under: FileManager.default.homeDirectoryForCurrentUser)
          .appending(path: "packages/standalone/current/bin")
      ],
    )
  ) {
    appServer = CodexAppServer(tool: tool)
  }

  func load() async -> QuotaReading {
    do throws(CodexAppServer.CallError) {
      let response: CodexQuotaResponse = try await appServer.call("account/rateLimits/read")
      return QuotaReading(response.snapshot)
    } catch .unconfirmed(.invalidRequest) {
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
        params: ConsumeParams(creditID: attempt.credit.id, idempotencyKey: attempt.idempotencyKey),
      )
      Logger.quota.info("codex reset outcome=\(response.outcome.rawValue, privacy: .public)")
      return .success(response.outcome)
    } catch .unconfirmed(let failure) where failure.isRefusal {
      Logger.quota.error("codex reset refused \(String(describing: failure), privacy: .public)")
      return .failure(.rejected(failure))
    } catch {
      Logger.quota.error("codex reset failed \(String(describing: error), privacy: .public)")
      return .failure(error)
    }
  }

  private let appServer: CodexAppServer
}

private struct ConsumeParams: Encodable {
  let creditID: String
  let idempotencyKey: UUID

  private enum CodingKeys: String, CodingKey {
    case creditID = "creditId"
    case idempotencyKey
  }
}

private struct ConsumeResponse: Decodable {
  let outcome: CodexQuotaResetOutcome
}
