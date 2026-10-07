import Foundation

struct GrokQuotaTestWorkspace {
    let tool: ScriptedToolWorkspace

    init(root: URL) {
        tool = ScriptedToolWorkspace(root: root)
    }

    var root: URL { tool.root }
    var requestsFile: URL { tool.requestsFile }
    var argumentsFile: URL { tool.argumentsFile }
    var directoryFile: URL { tool.directoryFile }
    var pidFile: URL { tool.pidFile }

    func makeAgent(
        billingResponse: String = response(),
        initializeResponse: String = #"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"authMethods":[]}}"#,
        beforeInitialize: String = "",
        beforeBilling: String = ""
    ) throws -> URL {
        try makeTestExecutable(
            in: root,
            script: """
                \(tool.prologue)
                IFS= read -r request || exit 1
                printf '%s\\n' "$request" > '\(requestsFile.path)'
                \(beforeInitialize)
                /bin/cat <<'INITIALIZE'
                \(initializeResponse)
                INITIALIZE
                IFS= read -r request || exit 1
                printf '%s\\n' "$request" >> '\(requestsFile.path)'
                \(beforeBilling)
                /bin/cat <<'BILLING'
                \(billingResponse)
                BILLING
                while IFS= read -r request; do
                  printf '%s\\n' "$request" >> '\(requestsFile.path)'
                done
                """
        )
    }

    static func response(
        config: String = """
        {"creditUsagePercent":25,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-09-01T00:00:00Z"}}
        """
    ) -> String {
        #"{"jsonrpc":"2.0","id":2,"result":{"config":\#(config)}}"#
    }
}
