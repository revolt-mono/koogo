import Foundation

/// Delegates credentials and billing to Grok's ACP server. Initialization performs the CLI's unattended authentication refresh; billing needs neither a session nor a model prompt.
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
        await QuotaReading { () throws(ToolFailure) in
            let response: GrokQuotaResponse = try await tool.session(
                ["--no-auto-update", "agent", "--no-leader", "stdio"],
                in: URL(filePath: "/tmp", directoryHint: .isDirectory)
            ) { streams in
                var connection = JSONRPCConnection(streams, dateDecodingStrategy: .iso8601)
                let initialized: InitializeResponse = try await connection.request(
                    "initialize",
                    params: InitializeParams()
                )
                guard initialized.protocolVersion == 1 else { throw ToolFailure.invalidMessage }
                return try await connection.request("_x.ai/billing", params: [String: String]())
            }
            return response.snapshot
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
