import Foundation

struct GrokQuotaTestWorkspace: ScriptedToolWorkspace {
    let root: URL

    func makeAgent(
        billingResponse: String = response(),
        initializeResponse: String = #"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"authMethods":[]}}"#,
        beforeBilling: String = ""
    ) throws -> URL {
        try makeTestExecutable(
            in: root,
            script: """
                \(prologue)
                IFS= read -r request || exit 1
                printf '%s\\n' "$request" > '\(requestsFile.path)'
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
        """,
        tier: String = #""SuperGrok Heavy""#
    ) -> String {
        #"{"jsonrpc":"2.0","id":2,"result":{"config":\#(config),"subscription_tier":\#(tier)}}"#
    }
}
