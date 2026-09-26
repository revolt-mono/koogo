import Foundation

struct CodexQuotaTestWorkspace {
    let root: URL

    func makeExecutable(script: String) throws -> URL {
        let executable = root.appending(path: UUID().uuidString)
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        return executable
    }

    static let resetCredit = """
        {"id":"credit-a","resetType":"codexRateLimits","status":"available","grantedAt":1700000000,"expiresAt":4102444800,"title":"Usage reset","description":"Reset eligible usage limits"}
        """

    /// A rate-limits read reply with one account window; reset credits are present only with a count.
    static func rateLimitsResponse(
        usedPercent: Int = 25,
        windowMinutes: Int = 300,
        resetCount: Int? = nil,
        credits: String? = nil
    ) -> String {
        let resetCredits = resetCount.map { #"{"availableCount":\#($0),"credits":\#(credits ?? "null")}"# } ?? "null"
        return """
            {"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":\(usedPercent),"windowDurationMins":\(windowMinutes),"resetsAt":1700000000},"secondary":null},"rateLimitsByLimitId":null,"rateLimitResetCredits":\(resetCredits)}}
            """
    }

    var quotaResponseFile: URL { root.appending(path: "quota-response.json") }
    var consumeRequestsFile: URL { root.appending(path: "consume-requests.jsonl") }
    var readRequestsFile: URL { root.appending(path: "read-requests.jsonl") }

    func lines(in file: URL) throws -> [Substring] {
        try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
    }

    /// A real stdio peer: reads are replaceable between launches and follow an unrelated
    /// notification, and every request is recorded. Method names are matched loosely because
    /// JSONEncoder escapes slashes.
    func makeAppServer(
        quotaResponse: String = rateLimitsResponse(resetCount: 1, credits: "[\(resetCredit)]"),
        consumeResponse: String = "{\"id\":2,\"result\":{\"outcome\":\"reset\"}}",
        onStart: String = "",
        onConsume: String = ""
    ) throws -> URL {
        let object = try JSONSerialization.jsonObject(with: Data(quotaResponse.utf8))
        try JSONSerialization.data(withJSONObject: object).write(to: quotaResponseFile)
        return try makeExecutable(
            script: """
                #!/bin/sh
                \(onStart)
                while IFS= read -r request; do
                  case "$request" in
                    *'"initialize"'*)
                      printf '%s\\n' '{"id":1,"result":{}}' ;;
                    *rateLimits*read*)
                      printf '%s\\n' "$request" >> '\(readRequestsFile.path)'
                      if [ ! -f '\(quotaResponseFile.path)' ]; then exit 0; fi
                      printf '%s\\n' '{"method":"unrelated/notification","params":{}}'
                      printf '%s\\n' "$(/bin/cat '\(quotaResponseFile.path)')" ;;
                    *ResetCredit*consume*)
                      printf '%s\\n' "$request" >> '\(consumeRequestsFile.path)'
                      \(onConsume)
                      printf '%s\\n' '\(consumeResponse)' ;;
                  esac
                done
                """
        )
    }
}
