import Foundation

struct CodexQuotaResponse: Decodable, Sendable {
    private let rateLimits: CodexRateLimitSnapshot
    private let rateLimitsByLimitID: [String: CodexRateLimitSnapshot]?
    private let rateLimitResetCredits: CodexRateLimitResetCredits?

    var snapshot: QuotaSnapshot? {
        QuotaSnapshot(
            account: rateLimits.windows,
            models: (rateLimitsByLimitID ?? [:]).compactMap { id, rateLimit in
                guard !id.isEmpty, id != (rateLimits.limitID ?? "codex") else { return nil }
                let title = rateLimit.limitName.flatMap { $0.isEmpty ? nil : $0 } ?? id
                return QuotaSnapshot.ModelLimits(
                    id: id,
                    title: title.caseInsensitiveCompare("gpt-reserve") == .orderedSame ? "Reserve quota" : title,
                    windows: rateLimit.windows
                )
            }
            .sorted {
                let order = $0.title.localizedCaseInsensitiveCompare($1.title)
                return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
            },
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

    /// The five-hour and weekly windows, whichever slot they arrive in; other durations are unknown.
    var windows: [QuotaWindow] {
        [window("Session", around: 300), window("Weekly", around: 10_080)].compactMap { $0 }
    }

    private enum CodingKeys: String, CodingKey {
        case limitID = "limitId"
        case limitName
        case primary
        case secondary
    }

    private func window(_ title: String, around expectedMinutes: Int64) -> QuotaWindow? {
        guard
            let window = [primary, secondary].compactMap({ $0 }).first(where: {
                guard let duration = $0.windowDurationMinutes else {
                    return false
                }
                return (expectedMinutes * 95 / 100)...(expectedMinutes * 105 / 100) ~= duration
            })
        else {
            return nil
        }
        return QuotaWindow(title: title, usedPercent: Double(window.usedPercent), resetsAt: window.resetsAt)
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
