import Foundation

struct UsageQuote: Sendable {
    struct Model: Hashable, Sendable {
        let id: String
        let displayName: String
    }

    let model: Model
    let costNanodollars: Decimal
}

extension UsageEvent {
    var quote: UsageQuote? {
        switch self {
        case .codex(let event): CodexUsagePricing.quote(for: event)
        case .claude(let event): ClaudeUsagePricing.quote(for: event)
        }
    }
}
