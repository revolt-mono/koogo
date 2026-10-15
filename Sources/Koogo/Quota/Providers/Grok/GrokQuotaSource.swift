import Foundation

/// grok initialization refreshes credentials unattended; billing needs no session or model prompt.
struct GrokQuotaSource: QuotaSource {
    private let tool: CommandLineTool

    init(
        executableCandidates: [URL] = CommandLineTool.candidates(
            named: "grok",
            preferring: [
                Provider.grok.home(under: FileManager.default.homeDirectoryForCurrentUser).appending(path: "bin")
            ]
        )
    ) {
        tool = CommandLineTool(candidates: executableCandidates, timeout: .seconds(30))
    }

    func load() async -> QuotaReading {
        do throws(ToolFailure) {
            return try await tool.session(["--no-auto-update", "agent", "--no-leader", "stdio"]) { streams in
                var connection = JSONRPCConnection(streams, dateDecodingStrategy: .iso8601)
                let initialized: InitializeResponse = try await connection.request(
                    "initialize",
                    params: InitializeParams()
                )
                guard initialized.protocolVersion == 1 else { throw ToolFailure.invalidMessage }
                do {
                    let response: GrokQuotaResponse = try await connection.request(
                        "_x.ai/billing",
                        params: [String: String]()
                    )
                    return QuotaReading(response.snapshot)
                } catch ToolFailure.rpc(code: -32000) {
                    // grok rejects billing requests locally unless signed in with an xai account.
                    return .unavailable(.noPlan)
                }
            }
        } catch {
            return .unavailable(QuotaUnavailability(error))
        }
    }
}

private struct InitializeParams: Encodable {
    let protocolVersion = 1
    let clientCapabilities: [String: String] = [:]
    let clientInfo = ["name": "koogo", "version": "1.0"]
}

private struct InitializeResponse: Decodable {
    let protocolVersion: Int
}
