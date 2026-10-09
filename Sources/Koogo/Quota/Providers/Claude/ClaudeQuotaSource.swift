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
        await QuotaReading { () throws(ToolFailure) in
            try await tool.session(
                Self.arguments,
                in: URL(filePath: "/tmp", directoryHint: .isDirectory)
            ) { streams in
                // The CLI shuts down and skips network reads once its input closes, so the request must stay open until the reply arrives.
                try await streams.write(Self.request)
                let reply = try await streams.first {
                    try Self.decoder.decode(ClaudeControlResponse.self, from: $0).reply
                }
                return reply.snapshot
            }
        }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            guard let date = Date(iso8601: try container.decode(String.self)) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "not an ISO 8601 date")
            }
            return date
        }
        return decoder
    }()
}
