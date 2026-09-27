import Foundation

struct ClaudeQuotaTestWorkspace {
    let root: URL

    var outputFile: URL { root.appending(path: "output.jsonl") }
    var callsFile: URL { root.appending(path: "calls") }
    var argumentsFile: URL { root.appending(path: "arguments") }

    func makeCLI(
        output: String = response(),
        beforeOutput: String = "",
        afterOutput: String = ""
    ) throws -> URL {
        try output.write(to: outputFile, atomically: true, encoding: .utf8)
        let executable = root.appending(path: "claude")
        try """
        #!/bin/sh
        printf 'usage\\n' >> '\(callsFile.path)'
        printf '%s\\n' "$@" > '\(argumentsFile.path)'
        \(beforeOutput)
        /bin/cat '\(outputFile.path)'
        \(afterOutput)
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return executable
    }

    static func response(rateLimits: String = limits) -> String {
        """
        {"type":"system","subtype":"init"}
        {"type":"assistant","usage_report":{"rate_limits":\(rateLimits)}}
        {"type":"result","subtype":"success","is_error":false,"num_turns":0,"total_cost_usd":0}
        """
    }

    static let limits = """
        {"limits":[
        {"kind":"weekly_scoped","percent":63,"resets_at":"2026-09-02T08:00:00+08:00","scope":{"model":{"display_name":"Fable"},"surface":null},"is_active":false},
        {"kind":"session","percent":12,"resets_at":"2026-09-01T00:00:00.125000+00:00","scope":null,"is_active":false},
        {"kind":"weekly_all","percent":29,"resets_at":"2026-09-03T00:00:00Z","scope":null,"is_active":true}
        ],"extra_usage":{"is_enabled":false}}
        """.replacingOccurrences(of: "\n", with: "")
}
