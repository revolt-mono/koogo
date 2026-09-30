import Foundation

/// The `get_usage` control reply of the Claude CLI's stream-json protocol. The plan windows are the fields
/// the CLI keeps even when it answers from its own cached snapshot; the raw server rows are dropped then.
struct ClaudeQuotaResponse: Decodable {
    /// The CLI ran but its output cannot be used: no reply before its output ended, an error reply, or a window
    /// with an unreadable reset time.
    struct Invalid: Error {}

    struct Window: Decodable {
        /// Only model-scoped windows carry a name.
        let displayName: String?
        /// Null while the window has not started.
        let utilization: Double?
        let resetsAt: String?

        func quotaWindow(_ title: String) throws -> QuotaWindow? {
            guard let utilization else { return nil }
            let resetsAt = try resetsAt.map { text in
                guard let date = Date(iso8601: text) else { throw Invalid() }
                return date
            }
            return QuotaWindow(title: title, usedPercent: utilization, resetsAt: resetsAt)
        }
    }

    struct RateLimits: Decodable {
        let fiveHour: Window?
        let sevenDay: Window?
        let modelScoped: [Window]?
    }

    /// Null for API-key sessions and while the usage endpoint cannot be reached.
    let rateLimits: RateLimits?

    /// Nil when the CLI succeeded but reported no usable window.
    func snapshot() throws -> QuotaSnapshot? {
        guard let rateLimits else { return nil }
        let account = try [
            rateLimits.fiveHour?.quotaWindow("Session"),
            rateLimits.sevenDay?.quotaWindow("Weekly"),
        ].compactMap { $0 }
        var named: [String: QuotaWindow] = [:]
        for entry in rateLimits.modelScoped ?? [] {
            guard let name = entry.displayName?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
                let window = try entry.quotaWindow(name)
            else { continue }
            named[name] = window
        }
        return QuotaSnapshot(windows: account + named.sorted { $0.key < $1.key }.map(\.value))
    }
}

/// One line of the CLI's stream-json output; everything but the reply to the one request sent is skipped.
struct ClaudeControlResponse: Decodable {
    struct Envelope: Decodable {
        let subtype: String
        let response: ClaudeQuotaResponse?
    }

    let type: String
    let response: Envelope?

    /// Nil for any event other than a control reply; an error reply is invalid output.
    var reply: ClaudeQuotaResponse? {
        get throws {
            guard type == "control_response", let response else { return nil }
            guard response.subtype == "success", let reply = response.response else {
                throw ClaudeQuotaResponse.Invalid()
            }
            return reply
        }
    }
}
