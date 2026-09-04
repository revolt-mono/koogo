import Foundation

struct CodexQuotaResponse: Decodable {
    private let rateLimits: CodexRateLimitSnapshot
    private let rateLimitsByLimitID: [String: CodexRateLimitSnapshot]?
    private let rateLimitResetCredits: CodexRateLimitResetCredits?

    var snapshot: CodexQuotaSnapshot? {
        CodexQuotaSnapshot(
            account: CodexQuotaSnapshot.Account(
                limits: rateLimits.limits,
                resetCredits: rateLimitResetCredits?.snapshot
            ),
            models: (rateLimitsByLimitID ?? [:]).compactMap { id, rateLimit in
                guard id != (rateLimits.limitID ?? "codex"), let limits = rateLimit.limits else {
                    return nil
                }
                return CodexQuotaSnapshot.Model(id: id, title: rateLimit.limitName, limits: limits)
            }
            .sorted {
                let order = $0.title.localizedCaseInsensitiveCompare($1.title)
                return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
            }
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

    var limits: CodexQuotaSnapshot.Limits? {
        CodexQuotaSnapshot.Limits(
            fiveHour: window(around: 300),
            weekly: window(around: 10_080)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case limitID = "limitId"
        case limitName
        case primary
        case secondary
    }

    private func window(around expectedMinutes: Int64) -> CodexQuotaSnapshot.Window? {
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
        return CodexQuotaSnapshot.Window(usedPercent: window.usedPercent, resetsAt: window.resetsAt)
    }
}

private struct CodexRateLimitResetCredits: Decodable {
    let availableCount: Int64
    let credits: [Credit]?

    var snapshot: CodexQuotaSnapshot.ResetCredits? {
        guard let availableCount = UInt64(exactly: availableCount) else {
            return nil
        }
        return CodexQuotaSnapshot.ResetCredits(
            availableCount: availableCount,
            availableExpirations: credits?
                .filter { $0.status == "available" }
                .compactMap(\.expiresAt) ?? []
        )
    }

    struct Credit: Decodable {
        let status: String
        let expiresAt: Date?
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
