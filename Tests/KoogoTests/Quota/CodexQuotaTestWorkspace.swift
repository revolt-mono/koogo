import Darwin
import Foundation

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
