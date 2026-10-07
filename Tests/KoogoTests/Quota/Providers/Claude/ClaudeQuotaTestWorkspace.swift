import Foundation

struct ClaudeQuotaTestWorkspace {
    let tool: ScriptedToolWorkspace

    init(root: URL) {
        tool = ScriptedToolWorkspace(root: root)
    }

    var root: URL { tool.root }
    var requestsFile: URL { tool.requestsFile }
    var argumentsFile: URL { tool.argumentsFile }
    var directoryFile: URL { tool.directoryFile }

    func makeCLI(
        output: String = response(),
        beforeOutput: String = ""
    ) throws -> URL {
        try makeTestExecutable(
            in: root,
            script: """
                \(tool.prologue)
                \(beforeOutput)
                IFS= read -r request || exit 1
                printf '%s\\n' "$request" > '\(requestsFile.path)'
                /bin/cat <<'OUTPUT'
                \(output)
                OUTPUT
                """
        )
    }

    static func response(rateLimits: String = limits) -> String {
        """
        {"type":"system","subtype":"init","session_id":"s"}
        {"type":"control_response","response":{"subtype":"success","request_id":"1",\
        "response":{"session":{},"subscription_type":"max","rate_limits_available":true,\
        "rate_limits":\(rateLimits),"behaviors":null}}}
        """
    }

    static let limits = """
        {"five_hour":{"utilization":12,"resets_at":"2026-09-01T00:00:00.125000+00:00","limit_dollars":null},\
        "seven_day":{"utilization":29,"resets_at":"2026-09-03T00:00:00Z"},"seven_day_sonnet":null,\
        "model_scoped":[{"display_name":"Fable","utilization":63,"resets_at":"2026-09-02T08:00:00+08:00"}],\
        "limits":[{"kind":"weekly_all","group":"weekly","percent":29,"is_active":true}],\
        "extra_usage":{"is_enabled":false}}
        """
}
