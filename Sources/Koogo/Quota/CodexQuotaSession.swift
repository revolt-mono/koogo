import Darwin
import Foundation
import Synchronization

struct CodexQuotaSession: Sendable {
    private let executableURL: URL
    private let processGroup = ProcessGroupLifetime()

    init(executableURL: URL) {
        self.executableURL = executableURL
    }

    func run() async throws -> CodexQuotaSnapshot? {
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
                processGroup.finish()
            }
            try processGroup.start(process)

            var reader = LineReader(fileHandle: output.fileHandleForReading)
            try send(
                RPCRequest(
                    method: "initialize",
                    id: 1,
                    params: InitializeParams(
                        clientInfo: ClientInfo(name: "koogo", title: "Koogo", version: "1.0")
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
            processGroup.terminate()
        }
    }

    private func send<Value: Encodable>(_ value: Value, to handle: FileHandle) throws {
        var data = try JSONEncoder().encode(value)
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }

    private func response<Value: Decodable>(
        id: Int,
        from reader: inout LineReader
    ) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        while let data = try reader.nextLine() {
            guard let envelope = try? decoder.decode(RPCEnvelope.self, from: data), envelope.id == id
            else {
                continue
            }
            return try decoder.decode(RPCSuccess<Value>.self, from: data).result
        }
        throw Failure()
    }
}

private struct Failure: Error {}

private final class ProcessGroupLifetime: Sendable {
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
                preconditionFailure("process group lifetime cannot start twice")
            }
        }
    }

    func finish() {
        state.withLock { state in
            if case .terminating(let process) = state,
                Self.processGroupExists(process.processIdentifier)
            {
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
        guard
            let process = state.withLock({ state -> Process? in
                guard case .terminating(let process) = state else {
                    return nil
                }
                state = .stopped
                return process
            })
        else {
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

private struct RPCSuccess<Result: Decodable>: Decodable {
    let result: Result

    private enum CodingKeys: CodingKey {
        case result
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard !container.contains(.error) else {
            throw Failure()
        }
        result = try container.decode(Result.self, forKey: .result)
    }
}

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
    let rateLimits: RateLimitSnapshot
    let rateLimitsByLimitID: [String: RateLimitSnapshot]?
    let rateLimitResetCredits: RateLimitResetCredits?

    var snapshot: CodexQuotaSnapshot? {
        CodexQuotaSnapshot(
            account: CodexQuotaSnapshot.Account(
                limits: rateLimits.limits,
                resetCredits: rateLimitResetCredits?.snapshot
            ),
            models: (rateLimitsByLimitID ?? [:]).compactMap { id, rateLimit in
                guard id != (rateLimits.limitID ?? "codex"), let limits = rateLimit.limits else {
                    return nil
                }
                return CodexQuotaSnapshot.Model(id: id, title: rateLimit.limitName, limits: limits)
            }
            .sorted {
                let order = $0.title.localizedCaseInsensitiveCompare($1.title)
                return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
            }
        )
    }

    private enum CodingKeys: String, CodingKey {
        case rateLimits
        case rateLimitsByLimitID = "rateLimitsByLimitId"
        case rateLimitResetCredits
    }
}

private struct RateLimitSnapshot: Decodable {
    let limitID: String?
    let limitName: String?
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?

    var limits: CodexQuotaSnapshot.Limits? {
        CodexQuotaSnapshot.Limits(
            fiveHour: window(around: 300),
            weekly: window(around: 10_080)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case limitID = "limitId"
        case limitName
        case primary
        case secondary
    }

    private func window(around expectedMinutes: Int64) -> CodexQuotaSnapshot.Window? {
        guard
            let window = [primary, secondary].compactMap({ $0 }).first(where: {
                guard let duration = $0.windowDurationMinutes, duration > 0 else {
                    return false
                }
                return (expectedMinutes * 95 / 100)...(expectedMinutes * 105 / 100) ~= duration
            })
        else {
            return nil
        }
        return CodexQuotaSnapshot.Window(usedPercent: window.usedPercent, resetsAt: window.resetsAt)
    }
}

private struct RateLimitResetCredits: Decodable {
    let availableCount: Int64
    let credits: [Credit]?

    var snapshot: CodexQuotaSnapshot.ResetCredits? {
        guard let availableCount = UInt64(exactly: availableCount) else {
            return nil
        }
        return CodexQuotaSnapshot.ResetCredits(
            availableCount: availableCount,
            availableExpirations: credits?
                .filter { $0.status == "available" }
                .compactMap(\.expiresAt) ?? []
        )
    }

    struct Credit: Decodable {
        let status: String
        let expiresAt: Date?
    }
}

private struct RateLimitWindow: Decodable {
    let usedPercent: Int
    let windowDurationMinutes: Int64?
    let resetsAt: Date?

    private enum CodingKeys: String, CodingKey {
        case usedPercent
        case windowDurationMinutes = "windowDurationMins"
        case resetsAt
    }
}
