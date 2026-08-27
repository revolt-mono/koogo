import Darwin
import Foundation
import Synchronization

struct CodexQuotaSnapshot: Equatable, Sendable {
    struct Bucket: Equatable, Sendable {
        let fiveHour: Window?
        let weekly: Window?

        fileprivate init?(fiveHour: Window?, weekly: Window?) {
            guard fiveHour != nil || weekly != nil else {
                return nil
            }
            self.fiveHour = fiveHour
            self.weekly = weekly
        }
    }

    struct CodexBucket: Equatable, Sendable {
        let quota: Bucket?
        let availableResetCount: Int?

        fileprivate init?(quota: Bucket?, availableResetCount: Int?) {
            guard quota != nil || availableResetCount != nil else {
                return nil
            }
            self.quota = quota
            self.availableResetCount = availableResetCount
        }
    }

    struct ModelBucket: Equatable, Identifiable, Sendable {
        let id: String
        let title: String
        let quota: Bucket
    }

    struct Window: Equatable, Sendable {
        let remainingPercent: Int
        let resetsAt: Date?

        fileprivate init(usedPercent: Int, resetsAt: Int64?) {
            remainingPercent = 100 - min(max(usedPercent, 0), 100)
            self.resetsAt = resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        }
    }

    let codex: CodexBucket?
    let modelBuckets: [ModelBucket]

    fileprivate init?(codex: CodexBucket?, modelBuckets: [ModelBucket]) {
        guard codex != nil || !modelBuckets.isEmpty else {
            return nil
        }
        self.codex = codex
        self.modelBuckets = modelBuckets
    }
}

struct CodexQuotaService: Sendable {
    private struct Failure: Error {}

    private let executableURL: URL?

    init(executableURL: URL? = nil) {
        self.executableURL = executableURL
    }

    @concurrent
    func fetch() async -> CodexQuotaSnapshot? {
        guard let executableURL = executableURL ?? Self.findExecutable() else {
            return nil
        }

        let processLifetime = ProcessLifetime()
        do {
            return try await withThrowingTaskGroup(of: CodexQuotaSnapshot?.self) { group in
                group.addTask {
                    try await Self.runSession(
                        executableURL: executableURL,
                        processLifetime: processLifetime
                    )
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(15))
                    throw Failure()
                }

                guard let result = try await group.next() else {
                    throw Failure()
                }
                group.cancelAll()
                return result
            }
        } catch {
            return nil
        }
    }

    private static func findExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates = [
            home.appending(path: ".codex/packages/standalone/current/bin/codex"),
            home.appending(path: ".local/bin/codex"),
            URL(filePath: "/opt/homebrew/bin/codex"),
            URL(filePath: "/usr/local/bin/codex"),
        ]
        candidates.append(contentsOf: (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(filePath: String($0)).appending(path: "codex") })

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func runSession(
        executableURL: URL,
        processLifetime: ProcessLifetime
    ) async throws -> CodexQuotaSnapshot? {
        try await withTaskCancellationHandler {
            let process = Process()
            let input = Pipe()
            let output = Pipe()
            guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
                throw Failure()
            }
            process.executableURL = executableURL
            process.arguments = ["app-server", "--stdio"]
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = [executableURL.deletingLastPathComponent().path, environment["PATH"]]
                .compactMap { $0 }
                .joined(separator: ":")
            process.environment = environment

            defer {
                try? input.fileHandleForWriting.close()
                if process.isRunning {
                    process.waitUntilExit()
                }
                try? output.fileHandleForReading.close()
                processLifetime.finish()
            }
            try processLifetime.start(process)

            var reader = LineReader(fileHandle: output.fileHandleForReading)
            try send(
                RPCRequest(
                    method: "initialize",
                    id: 1,
                    params: InitializeParams(
                        clientInfo: ClientInfo(
                            name: "koogo",
                            title: "Koogo",
                            version: "1.0"
                        )
                    )
                ),
                to: input.fileHandleForWriting
            )
            let _: InitializeResponse = try response(id: 1, from: &reader)
            try send(RPCNotification(method: "initialized"), to: input.fileHandleForWriting)

            try send(
                RPCRequestWithoutParams(method: "account/rateLimits/read", id: 2),
                to: input.fileHandleForWriting
            )
            let payload: RateLimitsResponse = try response(id: 2, from: &reader)
            return payload.snapshot
        } onCancel: {
            processLifetime.terminate()
        }
    }

    private static func send<Value: Encodable>(_ value: Value, to handle: FileHandle) throws {
        var data = try JSONEncoder().encode(value)
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }

    private static func response<Value: Decodable>(
        id: Int,
        from reader: inout LineReader
    ) throws -> Value {
        let decoder = JSONDecoder()

        while let data = try reader.nextLine() {
            guard let envelope = try? decoder.decode(RPCEnvelope.self, from: data), envelope.id == id else {
                continue
            }
            let response = try decoder.decode(RPCResponse<Value>.self, from: data)
            if response.error != nil {
                throw Failure()
            }
            guard let result = response.result else {
                throw Failure()
            }
            return result
        }

        throw Failure()
    }

    private final class ProcessLifetime: Sendable {
        private enum State {
            case pending
            case running(Process)
            case terminating(Process)
            case stopped
        }

        private let state = Mutex(State.pending)

        func start(_ process: Process) throws {
            try state.withLock { state in
                switch state {
                case .pending:
                    try process.run()
                    guard getpgid(process.processIdentifier) == process.processIdentifier else {
                        Darwin.kill(process.processIdentifier, SIGKILL)
                        process.waitUntilExit()
                        throw Failure()
                    }
                    state = .running(process)
                case .stopped:
                    throw CancellationError()
                case .running, .terminating:
                    preconditionFailure("process lifetime cannot start twice")
                }
            }
        }

        func finish() {
            state.withLock { state in
                if case .terminating(let process) = state,
                   Self.processGroupExists(process.processIdentifier) {
                    return
                }
                state = .stopped
            }
        }

        func terminate() {
            let process = state.withLock { state -> Process? in
                switch state {
                case .pending:
                    state = .stopped
                    return nil
                case .running(let process) where Self.processGroupExists(process.processIdentifier):
                    state = .terminating(process)
                    return process
                case .running:
                    state = .stopped
                    return nil
                case .terminating, .stopped:
                    return nil
                }
            }
            guard let process else {
                return
            }
            if process.isRunning {
                Darwin.kill(process.processIdentifier, SIGTERM)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                self.forceTerminate()
            }
        }

        private func forceTerminate() {
            guard let process = state.withLock({ state -> Process? in
                guard case .terminating(let process) = state else {
                    return nil
                }
                state = .stopped
                return process
            }) else {
                return
            }

            Darwin.kill(-process.processIdentifier, SIGKILL)
        }

        private static func processGroupExists(_ processGroupIdentifier: Int32) -> Bool {
            Darwin.kill(-processGroupIdentifier, 0) != -1 || errno != ESRCH
        }
    }

    private struct LineReader {
        let fileHandle: FileHandle
        var buffer = Data()

        mutating func nextLine() throws -> Data? {
            while true {
                if let newline = buffer.firstIndex(of: 0x0A) {
                    let line = Data(buffer[..<newline])
                    buffer.removeSubrange(...newline)
                    return line
                }

                let chunk = fileHandle.availableData
                if chunk.isEmpty {
                    guard !buffer.isEmpty else {
                        return nil
                    }
                    defer { buffer.removeAll() }
                    return buffer
                }
                buffer.append(chunk)
                guard buffer.count <= 4 * 1_024 * 1_024 else {
                    throw Failure()
                }
            }
        }
    }

    private struct RPCRequest<Params: Encodable>: Encodable {
        let method: String
        let id: Int
        let params: Params
    }

    private struct RPCRequestWithoutParams: Encodable {
        let method: String
        let id: Int
    }

    private struct RPCNotification: Encodable {
        let method: String
    }

    private struct RPCEnvelope: Decodable {
        let id: Int?
    }

    private struct RPCResponse<Result: Decodable>: Decodable {
        let result: Result?
        let error: RPCError?
    }

    private struct RPCError: Decodable {}

    private struct InitializeParams: Encodable {
        let clientInfo: ClientInfo
    }

    private struct ClientInfo: Encodable {
        let name: String
        let title: String
        let version: String
    }

    private struct InitializeResponse: Decodable {}

    private struct RateLimitsResponse: Decodable {
        let rateLimitsByLimitID: [String: RateLimitSnapshot]?
        let rateLimitResetCredits: ResetCredits?

        var snapshot: CodexQuotaSnapshot? {
            let rateLimits = rateLimitsByLimitID ?? [:]
            return CodexQuotaSnapshot(
                codex: CodexQuotaSnapshot.CodexBucket(
                    quota: rateLimits["codex"]?.bucket,
                    availableResetCount: rateLimitResetCredits?.availableCount
                ),
                modelBuckets: rateLimits.compactMap { id, rateLimit in
                    guard id != "codex", let quota = rateLimit.bucket else {
                        return nil
                    }
                    return CodexQuotaSnapshot.ModelBucket(
                        id: id,
                        title: rateLimit.limitName ?? id,
                        quota: quota
                    )
                }
                .sorted {
                    $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
            )
        }

        private enum CodingKeys: String, CodingKey {
            case rateLimitsByLimitID = "rateLimitsByLimitId"
            case rateLimitResetCredits
        }
    }

    private struct RateLimitSnapshot: Decodable {
        let limitName: String?
        let primary: RateLimitWindow?
        let secondary: RateLimitWindow?

        var bucket: CodexQuotaSnapshot.Bucket? {
            CodexQuotaSnapshot.Bucket(
                fiveHour: window(around: 300),
                weekly: window(around: 10_080)
            )
        }

        private func window(around expectedMinutes: Int64) -> CodexQuotaSnapshot.Window? {
            guard let window = [primary, secondary].compactMap({ $0 }).first(where: {
                guard let duration = $0.windowDurationMinutes, duration > 0 else {
                    return false
                }
                return (expectedMinutes * 95 / 100)...(expectedMinutes * 105 / 100) ~= duration
            }) else {
                return nil
            }
            return CodexQuotaSnapshot.Window(
                usedPercent: window.usedPercent,
                resetsAt: window.resetsAt
            )
        }
    }

    private struct RateLimitWindow: Decodable {
        let usedPercent: Int
        let windowDurationMinutes: Int64?
        let resetsAt: Int64?

        private enum CodingKeys: String, CodingKey {
            case usedPercent
            case windowDurationMinutes = "windowDurationMins"
            case resetsAt
        }
    }

    private struct ResetCredits: Decodable {
        let availableCount: Int
    }
}
