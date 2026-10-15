import Foundation

/// claude's cached usage replies retain plan windows but omit raw server rows.
struct ClaudeQuotaResponse: Decodable {
    struct Window: Decodable {
        let displayName: String?
        /// null before the window starts.
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

    /// false for logins outside plan limits; claude determines eligibility locally, including offline.
    let rateLimitsAvailable: Bool
    /// null while the usage endpoint is unreachable.
    let rateLimits: RateLimits?
    let subscriptionType: String?

    var reading: QuotaReading {
        guard rateLimitsAvailable else { return .unavailable(.noPlan) }
        guard let rateLimits else { return .unavailable(.emptyLimits) }
        let account = [
            rateLimits.fiveHour?.quotaWindow("Session"),
            rateLimits.sevenDay?.quotaWindow("Weekly"),
        ].compactMap { $0 }
        var named: [String: QuotaWindow] = [:]
        for entry in rateLimits.modelScoped ?? [] {
            guard let name = entry.displayName?.trimmingCharacters(in: .whitespaces).nonEmpty,
                let window = entry.quotaWindow(name)
            else { continue }
            named[name] = window
        }
        return QuotaReading(
            QuotaSnapshot(
                plan: subscriptionType.map(\.capitalized),
                windows: account + named.sorted { $0.key < $1.key }.map(\.value)
            )
        )
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
                throw ToolFailure.invalidMessage
            }
            return reply
        }
    }
}
