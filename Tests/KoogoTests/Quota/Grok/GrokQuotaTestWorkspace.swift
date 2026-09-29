import Foundation

struct GrokQuotaTestWorkspace {
    let root: URL

    var requestsFile: URL { root.appending(path: "requests.jsonl") }
    var argumentsFile: URL { root.appending(path: "arguments") }
    var directoryFile: URL { root.appending(path: "directory") }
    var pidFile: URL { root.appending(path: "pid") }

    /// A sequential ACP peer. Records every client message, including unexpected session or prompt requests.
    func makeAgent(
        billingResponse: String = response(),
        initializeResponse: String = #"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"authMethods":[]}}"#,
        beforeInitialize: String = "",
        beforeBilling: String = ""
    ) throws -> URL {
        try makeTestExecutable(
            in: root,
            script: """
                #!/bin/sh
                printf '%s\\n' "$$" > '\(pidFile.path)'
                printf '%s\\n' "$@" > '\(argumentsFile.path)'
                pwd > '\(directoryFile.path)'
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
