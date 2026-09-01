import Foundation

enum UsageProvider: String, Equatable, Sendable, Codable, CodingKeyRepresentable {
    case codex
    case claude
    case piAgent
}

enum UsageModelReference: Hashable, Sendable {
    case codex(id: String, name: String)
    case claude(id: String, name: String)
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
