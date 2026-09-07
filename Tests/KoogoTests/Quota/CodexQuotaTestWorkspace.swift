import Darwin
import Foundation

@testable import Koogo

struct CodexQuotaTestWorkspace {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() throws {
        try FileManager.default.removeItem(at: root)
    }

    func makeExecutable(
        shebang: String = "#!/bin/sh",
        launchMarker: URL? = nil,
        responseDelay: TimeInterval = 0,
        rateLimitsResponse: String
    ) throws -> URL {
        let launchLine = launchMarker.map { "printf 'launch\\n' >> '\($0.path)'" } ?? ":"
        return try makeExecutable(
            script: """
                \(shebang)
                \(launchLine)
                IFS= read -r initialize
                printf '%s\\n' '{"id":1,"result":{}}'
                IFS= read -r initialized
                IFS= read -r rate_limits
                printf '%s\\n' '{"method":"unrelated/notification","params":{}}'
                sleep \(responseDelay)
                printf '%s\\n' '\(rateLimitsResponse)'
                """
        )
    }

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

    static func resetQuotaResponse(
        count: Int = 1,
        credits: String = "[\(resetCredit)]",
        usedPercent: Int = 50
    ) -> String {
        """
        {"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":\(usedPercent),"windowDurationMins":300}},"rateLimitResetCredits":{"availableCount":\(count),"credits":\(credits)}}}
        """
    }

    static func resetAttempt() -> CodexQuotaResetAttempt {
        CodexQuotaResetAttempt(
            credit: CodexQuotaSnapshot.ResetCredit(
                id: "credit-a",
                title: "Usage reset",
                expiresAt: Date(timeIntervalSince1970: 4_102_444_800)
            )
        )
    }

    var quotaResponseFile: URL { root.appending(path: "quota-response.json") }
    var consumeRequestsFile: URL { root.appending(path: "consume-requests.jsonl") }
    var readRequestsFile: URL { root.appending(path: "read-requests.jsonl") }

    /// A real stdio peer: reads are replaceable between launches, and every write is recorded.
    /// Method names are matched loosely because JSONEncoder escapes slashes.
    func makeResetExecutable(
        quotaResponse: String = resetQuotaResponse(),
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

    /// Reads a pid a stub server wrote to `marker` and waits up to three seconds for it to be gone.
    func processExited(pidWrittenTo marker: URL) async throws -> Bool {
        let contents = try String(contentsOf: marker, encoding: .utf8)
        guard let pid = pid_t(contents.trimmingCharacters(in: .newlines)) else {
            return false
        }
        let deadline = ContinuousClock.now + .seconds(3)
        while kill(pid, 0) == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        return kill(pid, 0) == -1 && errno == ESRCH
    }
}
