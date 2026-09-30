import Foundation

struct CodexQuotaResponse: Decodable, Sendable {
    private let rateLimits: CodexRateLimitSnapshot
    private let rateLimitsByLimitID: [String: CodexRateLimitSnapshot]?
    private let rateLimitResetCredits: CodexRateLimitResetCredits?

    var snapshot: QuotaSnapshot? {
        let accountID = rateLimits.limitID ?? "codex"
        let named = (rateLimitsByLimitID ?? [:])
            .filter { id, _ in !id.isEmpty && id != accountID }
            .map { id, rateLimit in
                (id: id, name: rateLimit.limitName.flatMap { $0.isEmpty ? nil : $0 } ?? id, rateLimit: rateLimit)
            }
            .sorted {
                let order = $0.name.localizedCaseInsensitiveCompare($1.name)
                return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
            }
        return QuotaSnapshot(
            windows: rateLimits.windows(named: nil) + named.flatMap { $0.rateLimit.windows(named: $0.name) },
            resetCredits: rateLimitResetCredits?.snapshot
        )
    }

    private enum CodingKeys: String, CodingKey {
        case rateLimits
        case rateLimitsByLimitID = "rateLimitsByLimitId"
        case rateLimitResetCredits
    }
}

private struct CodexRateLimitSnapshot: Decodable {
    let limitID: String?
    let limitName: String?
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?

    func windows(named name: String?) -> [QuotaWindow] {
        let found = [("Session", 300), ("Weekly", 10_080)].compactMap { period, minutes in
            window(around: minutes).map { (period: period, window: $0) }
        }
        return found.map { period, window in
            let title = if let name { found.count == 1 ? name : "\(name) \(period)" } else { period }
            return QuotaWindow(title: title, usedPercent: Double(window.usedPercent), resetsAt: window.resetsAt)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case limitID = "limitId"
        case limitName
        case primary
        case secondary
    }

    private func window(around expectedMinutes: Int64) -> CodexRateLimitWindow? {
        let durations = (expectedMinutes * 95 / 100)...(expectedMinutes * 105 / 100)
        return [primary, secondary].compactMap { $0 }.first { window in
            window.windowDurationMinutes.map { durations ~= $0 } ?? false
        }
    }
}

private struct CodexRateLimitResetCredits: Decodable {
    let availableCount: Int64
    let credits: [Credit]?

    var snapshot: QuotaSnapshot.ResetCredits? {
        guard let availableCount = UInt64(exactly: availableCount) else {
            return nil
        }
        return QuotaSnapshot.ResetCredits(
            availableCount: availableCount,
            credits: credits?
                .filter { $0.status == "available" && $0.resetType == "codexRateLimits" }
                .sorted { ($0.expiresAt ?? .distantFuture, $0.id) < ($1.expiresAt ?? .distantFuture, $1.id) }
                .map {
                    QuotaSnapshot.ResetCredit(
                        id: $0.id,
                        title: $0.title ?? "Banked reset",
                        expiresAt: $0.expiresAt
                    )
                }
        )
    }

    struct Credit: Decodable {
        let id: String
        let resetType: String
        let status: String
        let expiresAt: Date?
        let title: String?
    }
}

private struct CodexRateLimitWindow: Decodable {
    let usedPercent: Int
    let windowDurationMinutes: Int64?
    let resetsAt: Date?

    private enum CodingKeys: String, CodingKey {
        case usedPercent
        case windowDurationMinutes = "windowDurationMins"
        case resetsAt
    }
}
