import Foundation

/// The `get_usage` control reply of the Claude CLI's stream-json protocol. The plan windows are the fields the CLI keeps even when it answers from its own cached snapshot; the raw server rows are dropped then.
struct ClaudeQuotaResponse: Decodable {
    struct Window: Decodable {
        let displayName: String?
        /// Null while the window has not started.
        let utilization: Double?
        let resetsAt: Date?

        func quotaWindow(_ title: String) -> QuotaWindow? {
            utilization.map { QuotaWindow(title: title, usedPercent: $0, resetsAt: resetsAt) }
        }
    }

    struct RateLimits: Decodable {
        let fiveHour: Window?
        let sevenDay: Window?
        let modelScoped: [Window]?
    }

    /// Null for API-key sessions and while the usage endpoint cannot be reached.
    let rateLimits: RateLimits?

    var snapshot: QuotaSnapshot? {
        guard let rateLimits else { return nil }
        let account = [
            rateLimits.fiveHour?.quotaWindow("Session"),
            rateLimits.sevenDay?.quotaWindow("Weekly"),
        ].compactMap { $0 }
        var named: [String: QuotaWindow] = [:]
        for entry in rateLimits.modelScoped ?? [] {
            guard let name = entry.displayName?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
                let window = entry.quotaWindow(name)
            else { continue }
            named[name] = window
        }
        return QuotaSnapshot(windows: account + named.sorted { $0.key < $1.key }.map(\.value))
    }
}

struct ClaudeControlResponse: Decodable {
    struct Envelope: Decodable {
        let subtype: String
        let response: ClaudeQuotaResponse?
    }

    let type: String
    let response: Envelope?

    var reply: ClaudeQuotaResponse? {
        get throws {
            guard type == "control_response", let response else { return nil }
            guard response.subtype == "success", let reply = response.response else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(codingPath: [], debugDescription: "the usage request failed")
                )
            }
            return reply
        }
    }
}
