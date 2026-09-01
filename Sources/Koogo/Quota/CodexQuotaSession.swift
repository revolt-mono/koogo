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
                RPCMessage(
                    method: "initialize",
                    id: 1,
                    params: ["clientInfo": ["name": "koogo", "title": "Koogo", "version": "1.0"]]
                ),
                to: input.fileHandleForWriting
            )
            let _: InitializeResponse = try response(id: 1, from: &reader)
            try send(RPCMessage(method: "initialized"), to: input.fileHandleForWriting)
            try send(RPCMessage(method: "account/rateLimits/read", id: 2), to: input.fileHandleForWriting)
            let payload: CodexQuotaResponse = try response(id: 2, from: &reader)
            // The one-shot session is complete; do not wait for app-server to notice stdin EOF.
            processGroup.terminate()
            return payload.snapshot
        } onCancel: {
            processGroup.terminate()
        }
    }

    private func send(_ message: RPCMessage, to handle: FileHandle) throws {
        var data = try JSONEncoder().encode(message)
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

/// Nil `id` marks a notification; nil `params` is omitted from the wire.
private struct RPCMessage: Encodable {
    let method: String
    var id: Int?
    var params: [String: [String: String]]?
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

private struct InitializeResponse: Decodable {}
