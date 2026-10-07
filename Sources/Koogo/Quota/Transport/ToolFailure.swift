/// Why a tool session gave no answer. Every transport error is one of these, so a caller classifies failures once.
enum ToolFailure: Error, Equatable, Sendable {
    /// No candidate path holds an executable.
    case notFound
    case timedOut
    case cancelled
    /// The tool exited, never ran, or closed its output before replying.
    case closed
    /// A reply was unreadable, oversized, or not the message the protocol expects.
    case invalidMessage
    case rpc(code: Int)
}
