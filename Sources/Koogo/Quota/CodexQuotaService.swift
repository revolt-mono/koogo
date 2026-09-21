import Foundation
import Synchronization

/// Why no quota is shown; surfaced in telemetry and the `--report` output.
enum CodexQuotaUnavailability: String, Error, Encodable, Sendable {
    case binaryNotFound
    case timedOut
    case sessionFailed
    case emptyLimits
}

struct CodexQuotaService: Sendable {
    private let executableURL: URL?
    private let timeout: Duration

    init(executableURL: URL? = nil, timeout: Duration = .seconds(15)) {
        self.executableURL = executableURL
        self.timeout = timeout
    }

    @concurrent
    func fetch() async -> Result<CodexQuotaSnapshot, CodexQuotaUnavailability> {
        let result: Result<CodexQuotaSnapshot, CodexQuotaUnavailability>
        do {
            let snapshot = try await run { try await $0.fetch() }
            result = snapshot.map(Result.success) ?? .failure(.emptyLimits)
        } catch let reason as CodexQuotaUnavailability {
            result = .failure(reason)
        } catch {
            result = .failure(.sessionFailed)
        }

        switch result {
        case .success:
            Telemetry.quota.info("fetch available")
        case .failure(let reason):
            Telemetry.quota.info("fetch unavailable reason=\(reason.rawValue, privacy: .public)")
        }
        return result
    }

    @concurrent
    func consume(_ attempt: CodexQuotaResetAttempt) async -> CodexQuotaResetResult {
        // Flipped right before the request is written, so a later failure may still have reached the server.
        let writeStarted = Mutex(false)
        let result: CodexQuotaResetResult
        do {
            let outcome = try await run { session in
                try await session.consume(attempt) { writeStarted.withLock { $0 = true } }
            }
            result = .completed(outcome)
        } catch {
            let failure: CodexQuotaResetFailure =
                switch error {
                case let error as CodexQuotaRPCError: .rpc(code: error.code)
                case let reason as CodexQuotaUnavailability: .unavailable(reason)
                default: .unavailable(.sessionFailed)
                }
            result = writeStarted.withLock { $0 } ? .unconfirmed(failure) : .rejected(failure)
        }

        switch result {
        case .completed(let outcome):
            Telemetry.quota.info("reset outcome=\(outcome.rawValue, privacy: .public)")
        case .rejected, .unconfirmed:
            Telemetry.quota.error("reset failed \(String(describing: result), privacy: .public)")
        }
        return result
    }

    private func run<Value: Sendable>(
        operation: @escaping @Sendable (CodexQuotaSession) async throws -> Value
    ) async throws -> Value {
        guard let executableURL = executableURL ?? Self.findExecutable() else {
            throw CodexQuotaUnavailability.binaryNotFound
        }
        return try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask { try await operation(CodexQuotaSession(executableURL: executableURL)) }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw CodexQuotaUnavailability.timedOut
            }
            defer { group.cancelAll() }
            // Two racing children are in flight, so next() cannot return nil.
            return try await group.next()!
        }
    }

    private static func findExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates =
            [
                home.appending(path: ".codex/packages/standalone/current/bin/codex"),
                home.appending(path: ".local/bin/codex"),
                URL(filePath: "/opt/homebrew/bin/codex"),
                URL(filePath: "/usr/local/bin/codex"),
            ]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(filePath: String($0)).appending(path: "codex") }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
