import Foundation

enum ClaudeQuotaUnavailability: String, Error, Encodable, Sendable {
    case binaryNotFound
    case timedOut
    case sessionFailed
    case emptyLimits
}

typealias ClaudeQuotaModel = QuotaModel<ClaudeQuotaService>

/// Delegates authentication and quota access to the local Claude CLI, without reading credentials
/// or making HTTP requests from the app.
struct ClaudeQuotaService: QuotaService {
    private let executableCandidates: [URL]
    private let timeout: Duration

    init(
        executableCandidates: [URL] = ClaudeQuotaService.standardCandidates(),
        timeout: Duration = .seconds(15)
    ) {
        self.executableCandidates = executableCandidates
        self.timeout = timeout
    }

    static func standardCandidates() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let installs = [
            home.appending(path: ".local/bin/claude"),
            URL(filePath: "/opt/homebrew/bin/claude"),
            URL(filePath: "/usr/local/bin/claude"),
        ]
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
        return installs + path.map { URL(filePath: String($0)).appending(path: "claude") }
    }

    @concurrent
    func fetch() async -> Result<ClaudeQuotaSnapshot, ClaudeQuotaUnavailability> {
        let result: Result<ClaudeQuotaSnapshot, ClaudeQuotaUnavailability>
        do {
            guard
                let executable = executableCandidates.first(where: {
                    FileManager.default.isExecutableFile(atPath: $0.path)
                })
            else { throw ClaudeQuotaUnavailability.binaryNotFound }
            let snapshot = try await ProcessGroupLifetime.run(timeout: timeout) { processGroup in
                try Self.blockingRun(executable: executable, processGroup: processGroup)
            }
            result = snapshot.map(Result.success) ?? .failure(.emptyLimits)
        } catch is ProcessGroupLifetime.TimedOut {
            result = .failure(.timedOut)
        } catch {
            result = .failure(error as? ClaudeQuotaUnavailability ?? .sessionFailed)
        }
        switch result {
        case .success:
            Telemetry.quota.info("claude fetch available")
        case .failure(let reason):
            Telemetry.quota.info("claude fetch unavailable reason=\(reason.rawValue, privacy: .public)")
        }
        return result
    }

    private static func blockingRun(
        executable: URL,
        processGroup: ProcessGroupLifetime
    ) throws -> ClaudeQuotaSnapshot? {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        // Keep quota reads isolated from project settings, hooks, tools, and saved sessions.
        process.arguments = [
            "--setting-sources", "",
            "--settings", #"{"disableAllHooks":true,"remoteControlAtStartup":false}"#,
            "--strict-mcp-config", "--tools", "",
            "--no-session-persistence", "--max-budget-usd", "0.01",
            "-p", "/usage", "--output-format", "stream-json", "--verbose",
        ]
        process.currentDirectoryURL = URL(filePath: "/tmp", directoryHint: .isDirectory)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = [executable.deletingLastPathComponent().path, environment["PATH"]]
            .compactMap { $0 }
            .joined(separator: ":")
        process.environment = environment

        defer {
            processGroup.terminate()
            if process.isRunning {
                process.waitUntilExit()
            }
            try? output.fileHandleForReading.close()
            processGroup.finish()
        }
        try processGroup.start(process)
        var data = Data()
        while let chunk = try output.fileHandleForReading.read(upToCount: 64 * 1_024), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= 4 * 1_024 * 1_024 else { throw ClaudeQuotaUnavailability.sessionFailed }
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ClaudeQuotaUnavailability.sessionFailed }
        return try ClaudeQuotaResponse.snapshot(from: data)
    }
}
