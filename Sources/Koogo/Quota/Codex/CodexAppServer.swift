import Foundation
import Synchronization

/// Owns the Codex handshake and distinguishes setup failures from requests that may have reached
/// the server. Each call starts one app-server process and stops it after the reply.
struct CodexAppServer: Sendable {
    enum Failure: Error, Equatable, Sendable {
        case binaryNotFound
        case timedOut
        case sessionFailed
        case methodNotFound
        case rpc(code: Int)
    }

    enum CallError: Error, Equatable {
        /// The operation was never sent; a reset attempt can be cancelled.
        case rejected(Failure)
        /// The operation may have reached the server; a reset retry must keep the same idempotency key.
        case unconfirmed(Failure)

        var failure: Failure {
            switch self {
            case .rejected(let failure), .unconfirmed(let failure): failure
            }
        }
    }

    let tool: CommandLineTool

    func call<Value: Decodable & Sendable, Params: Encodable & Sendable>(
        _ method: String,
        params: Params? = Optional<Never>.none
    ) async throws(CallError) -> Value {
        // The timeout races the blocking session. Only the request write crosses the uncertain-outcome boundary.
        let requestStarted = Mutex(false)
        do {
            return try await tool.session(["app-server", "--stdio"]) { input, output in
                var connection = JSONRPCConnection(
                    input: input,
                    output: output,
                    dateDecodingStrategy: .secondsSince1970
                )
                let _: InitializeResponse = try connection.request(
                    "initialize",
                    params: ["clientInfo": ["name": "koogo", "title": "Koogo", "version": "1.0"]]
                )
                try connection.notify("initialized")
                requestStarted.withLock { $0 = true }
                return try connection.request(method, params: params)
            }
        } catch {
            let failure: Failure =
                switch error {
                case CommandLineTool.Failure.notFound: .binaryNotFound
                case CommandLineTool.Failure.timedOut: .timedOut
                case JSONRPCConnection.Failure.rpc(code: -32601): .methodNotFound
                case JSONRPCConnection.Failure.rpc(let code): .rpc(code: code)
                default: .sessionFailed
                }
            throw requestStarted.withLock { $0 } ? .unconfirmed(failure) : .rejected(failure)
        }
    }
}

private struct InitializeResponse: Decodable {}
