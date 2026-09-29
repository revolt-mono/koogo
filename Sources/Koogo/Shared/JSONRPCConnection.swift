import Foundation

/// A sequential, newline-delimited JSON-RPC connection. Owns request IDs, skips notifications and
/// unrelated replies, and accepts exactly one result or error for the current request.
struct JSONRPCConnection {
    enum Failure: Error {
        case closed
        case invalidMessage
        case rpc(code: Int)
    }

    private let input: FileHandle
    private var output: LineReader
    private let decoder: JSONDecoder
    private var nextID = 1

    init(
        input: FileHandle,
        output: LineReader,
        dateDecodingStrategy: JSONDecoder.DateDecodingStrategy
    ) {
        self.input = input
        self.output = output
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = dateDecodingStrategy
    }

    /// Nil parameters are omitted. Invalid replies and EOF fail the request; RPC errors retain their code.
    mutating func request<Value: Decodable, Params: Encodable>(
        _ method: String,
        params: Params? = Optional<Never>.none
    ) throws -> Value {
        let id = nextID
        nextID += 1
        try send(Request(id: id, method: method, params: params))
        while let line = try output.nextLine() {
            let header = try decoder.decode(Header.self, from: line)
            guard case .response(id) = header else { continue }
            return try decoder.decode(Response<Value>.self, from: line).result
        }
        throw Failure.closed
    }

    /// A notification has no request ID and expects no reply.
    func notify(_ method: String) throws {
        try send(Notification(method: method))
    }

    private func send(_ message: some Encodable) throws {
        var data = try JSONEncoder().encode(message)
        data.append(0x0A)
        try input.write(contentsOf: data)
    }
}

extension JSONRPCConnection {
    private enum CodingKeys: CodingKey {
        case id, method, result, error
    }

    private struct Request<Params: Encodable>: Encodable {
        let jsonrpc = "2.0"
        let id: Int
        let method: String
        let params: Params?
    }

    private struct Notification: Encodable {
        let jsonrpc = "2.0"
        let method: String
    }

    private enum Header: Decodable {
        case notification
        case response(Int)

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if container.contains(.method) {
                _ = try container.decode(String.self, forKey: .method)
                // Server-initiated requests are outside this connection's response-only contract.
                guard !container.contains(.id), !container.contains(.result), !container.contains(.error) else {
                    throw Failure.invalidMessage
                }
                self = .notification
            } else {
                self = .response(try container.decode(Int.self, forKey: .id))
            }
        }
    }

    private struct Response<Value: Decodable>: Decodable {
        let result: Value

        private struct RemoteError: Decodable {
            let code: Int
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard container.contains(.result) != container.contains(.error) else {
                throw Failure.invalidMessage
            }
            if container.contains(.error) {
                throw Failure.rpc(code: try container.decode(RemoteError.self, forKey: .error).code)
            }
            result = try container.decode(Value.self, forKey: .result)
        }
    }
}
