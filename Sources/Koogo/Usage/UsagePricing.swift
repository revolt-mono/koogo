import Foundation

enum UsagePricing {
    struct Model: Hashable, Sendable {
        let id: String
        let displayName: String
    }

    struct Quote: Sendable {
        let model: Model
        let costNanodollars: Decimal
    }

    static func quote(for event: UsageEvent) -> Quote? {
        switch event {
        case .codex(let event): CodexUsagePricing.quote(for: event)
        case .claude(let event): ClaudeUsagePricing.quote(for: event)
        }
    }
}
