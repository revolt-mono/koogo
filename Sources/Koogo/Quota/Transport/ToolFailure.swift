enum ToolFailure: Error, Equatable {
    case notFound
    case timedOut
    /// the tool exited, never ran, or closed output before replying.
    case closed
    /// a reply was unreadable, oversized, or outside the expected protocol.
    case invalidMessage
    case rpc(code: Int)

    static let parseError = Self.rpc(code: -32700)
    static let invalidRequest = Self.rpc(code: -32600)
    static let methodNotFound = Self.rpc(code: -32601)
    static let invalidParams = Self.rpc(code: -32602)

    /// json-rpc reserves these codes for requests refused before running.
    var isRefusal: Bool {
        [Self.parseError, .invalidRequest, .methodNotFound, .invalidParams].contains(self)
    }
}
