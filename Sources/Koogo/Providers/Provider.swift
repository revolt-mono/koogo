import Foundation

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

    func home(under root: URL) -> URL {
        let path =
            switch self {
            case .codex: ".codex"
            case .claude: ".claude"
            case .piAgent: ".pi/agent"
            case .grok: ".grok"
            }
        return root.appending(path: path, directoryHint: .isDirectory)
    }

    var quota: QuotaProvider? {
        QuotaProvider.allCases.first { $0.provider == self }
    }
}

enum QuotaProvider: String, CaseIterable, Sendable, Encodable, CodingKeyRepresentable {
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
