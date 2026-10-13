enum ToolFailure: Error, Equatable, Sendable {
    case notFound
    case timedOut
    /// The tool exited, never ran, or closed its output before replying.
    case closed
    /// A reply was unreadable, oversized, or not the message the protocol expects.
    case invalidMessage
    case rpc(code: Int)
}
