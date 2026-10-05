import Foundation

struct ClaudeQuotaSource: QuotaSource {
    private static let arguments = [
        "--setting-sources", "",
        "--settings", #"{"disableAllHooks":true,"remoteControlAtStartup":false}"#,
        "--strict-mcp-config", "--tools", "",
        "--no-session-persistence",
        "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
    ]
    private static let request = Data(
        """
        {"type":"control_request","request_id":"1","request":{"subtype":"get_usage","skip_behaviors":true}}\n
        """.utf8
    )

    private let tool: CommandLineTool

    init(
        executableCandidates: [URL] = CommandLineTool.candidates(named: "claude"),
        timeout: Duration = .seconds(15)
    ) {
        tool = CommandLineTool(candidates: executableCandidates, timeout: timeout)
    }

    func load() async -> QuotaReading {
        do {
            let response = try await tool.session(
                Self.arguments,
                in: URL(filePath: "/tmp", directoryHint: .isDirectory)
            ) { input, output in
                // The CLI shuts down and skips network reads once its input closes, so the request must stay open until the reply arrives.
                try input.write(contentsOf: Self.request)
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                var output = output
                while let line = try output.nextLine() {
                    if let reply = try decoder.decode(ClaudeControlResponse.self, from: line).reply {
                        return reply
                    }
                }
                throw ClaudeQuotaResponse.Invalid()
            }
            return try response.snapshot().map(QuotaReading.available) ?? .unavailable(.emptyLimits)
        } catch {
            return .unavailable(QuotaUnavailability(error))
        }
    }
}
