import Foundation
import Synchronization

/// Talks to `codex app-server --stdio`: each call launches the server, completes the handshake, sends one
/// JSON-RPC request, and stops the server. JSON-RPC error codes are interpreted only here.
struct CodexAppServer: Sendable {
    enum Failure: Error, Equatable, Sendable {
        case binaryNotFound
        case timedOut
        case sessionFailed
        /// JSON-RPC -32601: this Codex version does not know the method.
        case methodNotFound
        case rpc(code: Int)
    }

    struct CallError: Error {
        let failure: Failure
        /// The method request started writing, so the server may have acted on it.
        let requestMayHaveArrived: Bool
    }

    let tool: CommandLineTool

    /// Sends `method` without a params key.
    func call<Value: Decodable & Sendable>(_ method: String) async throws(CallError) -> Value {
        try await call(RPCMessage<Never>(method: method, id: 2))
    }

    func call<Value: Decodable & Sendable, Params: Encodable & Sendable>(
        _ method: String,
        params: Params
    ) async throws(CallError) -> Value {
        try await call(RPCMessage(method: method, id: 2, params: params))
    }

    private func call<Value: Decodable & Sendable, Params: Encodable & Sendable>(
        _ request: RPCMessage<Params>
    ) async throws(CallError) -> Value {
        // Flipped right before the request is written, so a later failure may still have reached the server.
        let requestStarted = Mutex(false)
        do {
            return try await tool.session(["app-server", "--stdio"]) { input, output in
                var connection = RPCConnection(input: input, reader: output)
                let _: InitializeResponse = try connection.request(
                    RPCMessage(
                        method: "initialize",
                        id: 1,
                        params: ["clientInfo": ["name": "koogo", "title": "Koogo", "version": "1.0"]]
                    )
                )
                try connection.send(RPCMessage<Never>(method: "initialized"))
                requestStarted.withLock { $0 = true }
                return try connection.request(request)
            }
        } catch {
            let failure: Failure =
                switch error {
                case let failure as Failure: failure
                case CommandLineTool.Failure.notFound: .binaryNotFound
                case CommandLineTool.Failure.timedOut: .timedOut
                case let error as RPCError where error.code == -32601: .methodNotFound
                case let error as RPCError: .rpc(code: error.code)
                default: .sessionFailed
                }
            throw CallError(failure: failure, requestMayHaveArrived: requestStarted.withLock { $0 })
        }
    }
}

private struct RPCConnection {
    let input: FileHandle
    var reader: LineReader

    func send<Params: Encodable & Sendable>(_ message: RPCMessage<Params>) throws {
        var data = try JSONEncoder().encode(message)
        data.append(0x0A)
        try input.write(contentsOf: data)
    }

    mutating func request<Value: Decodable, Params: Encodable & Sendable>(
        _ message: RPCMessage<Params>
    ) throws -> Value {
        try send(message)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        while let data = try reader.nextLine() {
            guard let envelope = try? decoder.decode(RPCEnvelope.self, from: data), envelope.id == message.id
            else {
                continue
            }
            return try decoder.decode(RPCSuccess<Value>.self, from: data).result
        }
        throw CodexAppServer.Failure.sessionFailed
    }
}

/// Nil `id` marks a notification; nil `params` is omitted from the wire.
private struct RPCMessage<Params: Encodable & Sendable>: Encodable, Sendable {
    let method: String
    var id: Int?
    var params: Params?
}

private struct RPCEnvelope: Decodable {
    let id: Int?
}

private struct RPCError: Decodable, Error {
    let code: Int
}

private struct RPCSuccess<Result: Decodable>: Decodable {
    let result: Result

    private enum CodingKeys: CodingKey {
        case result
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.error) {
            throw try container.decode(RPCError.self, forKey: .error)
        }
        result = try container.decode(Result.self, forKey: .result)
    }
}

private struct InitializeResponse: Decodable {}
