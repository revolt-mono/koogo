import Foundation

/// Delegates credentials and billing to Grok's ACP server. Initialization performs the CLI's unattended authentication refresh; billing needs neither a session nor a model prompt.
struct GrokQuotaSource: QuotaSource {
    private let tool: CommandLineTool

    init(
        executableCandidates: [URL] = CommandLineTool.candidates(
            named: "grok",
            preferring: [FileManager.default.homeDirectoryForCurrentUser.appending(path: ".grok/bin")]
        ),
        timeout: Duration = .seconds(30)
    ) {
        tool = CommandLineTool(candidates: executableCandidates, timeout: timeout)
    }

    func load() async -> QuotaReading {
        do {
            let response: GrokQuotaResponse = try await tool.session(
                ["--no-auto-update", "agent", "--no-leader", "stdio"],
                in: URL(filePath: "/tmp", directoryHint: .isDirectory)
            ) { input, output in
                var connection = JSONRPCConnection(input: input, output: output, dateDecodingStrategy: .iso8601)
                let initialized: InitializeResponse = try connection.request("initialize", params: InitializeParams())
                guard initialized.protocolVersion == 1 else { throw JSONRPCConnection.Failure.invalidMessage }
                return try connection.request("_x.ai/billing", params: [String: String]())
            }
            return response.snapshot.map(QuotaReading.available) ?? .unavailable(.emptyLimits)
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
