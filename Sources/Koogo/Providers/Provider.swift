enum Provider: String, CaseIterable, Sendable, Codable, CodingKeyRepresentable {
    case codex
    case claude
    case piAgent
    case grok

    var title: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .piAgent: "Pi"
        case .grok: "Grok"
        }
    }

    var symbolAsset: String {
        switch self {
        case .codex: "OpenAISymbol"
        case .claude: "ClaudeSymbol"
        case .piAgent: "PiSymbol"
        case .grok: "GrokSymbol"
        }
    }

    /// The tool's configuration directory, relative to the user's home.
    var homePath: String {
        switch self {
        case .codex: ".codex"
        case .claude: ".claude"
        case .piAgent: ".pi/agent"
        case .grok: ".grok"
        }
    }

    var quota: QuotaProvider? {
        switch self {
        case .codex: .codex
        case .claude: .claude
        case .grok: .grok
        case .piAgent: nil
        }
    }
}

/// A provider whose tool reports account limits.
enum QuotaProvider: String, CaseIterable, Sendable, Codable, CodingKeyRepresentable {
    case codex
    case claude
    case grok

    var provider: Provider {
        switch self {
        case .codex: .codex
        case .claude: .claude
        case .grok: .grok
        }
    }
}
