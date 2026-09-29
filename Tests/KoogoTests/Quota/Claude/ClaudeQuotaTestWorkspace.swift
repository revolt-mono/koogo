import Foundation

struct ClaudeQuotaTestWorkspace {
    let root: URL

    var requestsFile: URL { root.appending(path: "requests.jsonl") }
    var argumentsFile: URL { root.appending(path: "arguments") }
    var directoryFile: URL { root.appending(path: "directory") }

    /// A stream-json peer: records the client's first line, answers it with `output`, then exits.
    func makeCLI(
        output: String = response(),
        beforeOutput: String = ""
    ) throws -> URL {
        let executable = root.appending(path: "claude")
        try """
        #!/bin/sh
        printf '%s\\n' "$@" > '\(argumentsFile.path)'
        pwd > '\(directoryFile.path)'
        \(beforeOutput)
        IFS= read -r request || exit 1
        printf '%s\\n' "$request" > '\(requestsFile.path)'
        /bin/cat <<'OUTPUT'
        \(output)
        OUTPUT
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return executable
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
