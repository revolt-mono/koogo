enum ToolFailure: Error, Equatable {
    case notFound
    case timedOut
    /// the tool exited, never ran, or closed output before replying.
    case closed
    /// a reply was unreadable, oversized, or outside the expected protocol.
    case invalidMessage
    case rpc(code: Int)
}
