import Foundation

enum UsageProvider: String, CaseIterable, Sendable, Encodable, CodingKeyRepresentable {
    case codex
    case claude
    case piAgent
    case grok
}

enum UsageModelReference: Hashable, Sendable {
    case codex(id: String, name: String)
    case claude(id: String, name: String)
    case piAgent(provider: String, id: String)
    case grok(id: String, name: String)
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
