import Foundation

typealias ClaudeQuotaModel = QuotaModel<ClaudeQuotaService>

/// Delegates authentication and quota access to the local Claude CLI, without reading credentials
/// or making HTTP requests from the app.
struct ClaudeQuotaService: QuotaService {
    static let name = "claude"

    // Keep quota reads isolated from project settings, hooks, tools, and saved sessions.
    private static let arguments = [
        "--setting-sources", "",
        "--settings", #"{"disableAllHooks":true,"remoteControlAtStartup":false}"#,
        "--strict-mcp-config", "--tools", "",
        "--no-session-persistence", "--max-budget-usd", "0.01",
        "-p", "/usage", "--output-format", "stream-json", "--verbose",
    ]

    private let tool: CommandLineTool

    init(
        executableCandidates: [URL] = CommandLineTool.candidates(named: "claude"),
        timeout: Duration = .seconds(15)
    ) {
        tool = CommandLineTool(candidates: executableCandidates, timeout: timeout)
    }

    func load() async -> Result<ClaudeQuotaSnapshot, CLIQuotaUnavailability> {
        do {
            let output = try await tool.output(
                of: Self.arguments,
                in: URL(filePath: "/tmp", directoryHint: .isDirectory)
            )
            return try ClaudeQuotaResponse.snapshot(from: output).map(Result.success) ?? .failure(.emptyLimits)
        } catch {
            return .failure(CLIQuotaUnavailability(error))
        }
    }
}
