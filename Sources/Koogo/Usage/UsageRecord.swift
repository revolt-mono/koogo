import Foundation

enum UsageProvider: String, CaseIterable, Sendable, Encodable, CodingKeyRepresentable {
    case codex
    case claude
    case piAgent
    case grok
}

extension UsageProvider {
    var title: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .piAgent: "Pi"
        case .grok: "Grok"
        }
    }
}

enum UsageModelReference: Hashable, Sendable {
    case named(id: String, name: String)
    case piAgent(provider: String, id: String)
}

struct UsageRecord: Sendable {
    struct ModelTurn: Sendable {
        let model: UsageModelReference
        let reasoningEffort: String?
    }

    let timestamp: Date
    let processedTokens: UInt64
    let costUSD: Decimal
    let modelTurn: ModelTurn?
}

struct UsageQuote: Sendable {
    let model: UsageModelReference
    let costUSD: Decimal
}
