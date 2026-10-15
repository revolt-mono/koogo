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
        do throws(ToolFailure) {
            return try await tool.session(Self.arguments) { streams in
                var streams = streams
                // claude skips network reads after input closes; keep input open until the reply arrives.
                try await streams.write(Self.request)
                let reply = try await streams.first {
                    try Self.decoder.decode(ClaudeControlResponse.self, from: $0).reply
                }
                return reply.reading
            }
        } catch {
            return .unavailable(QuotaUnavailability(error))
        }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
