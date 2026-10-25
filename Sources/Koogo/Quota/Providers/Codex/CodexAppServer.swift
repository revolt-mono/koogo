import Foundation
import Synchronization

struct CodexAppServer: Sendable {
    /// unconfirmed requests may have reached the server; retry those writes with the same idempotency key.
    enum CallError: Error, Equatable {
        case rejected(ToolFailure)
        case unconfirmed(ToolFailure)

        var failure: ToolFailure {
            switch self {
            case .rejected(let failure), .unconfirmed(let failure): failure
            }
        }
    }

    let tool: CommandLineTool

    func call<Value: Decodable & Sendable, Params: Encodable & Sendable>(
        _ method: String,
        params: Params? = Never?.none
    ) async throws(CallError) -> Value {
        let requestStarted = Mutex(false)
        do {
            return try await tool.session(["app-server", "--stdio"]) { streams in
                var connection = JSONRPCConnection(streams, dateDecodingStrategy: .secondsSince1970)
                let _: InitializeResponse = try await connection.request(
                    "initialize",
                    params: ["clientInfo": ["name": "koogo", "title": "Koogo", "version": "1.0"]]
                )
                try await connection.notify("initialized")
                requestStarted.withLock { $0 = true }
                return try await connection.request(method, params: params)
            }
        } catch {
            throw requestStarted.withLock { $0 } ? .unconfirmed(error) : .rejected(error)
        }
    }
}

private struct InitializeResponse: Decodable {}
