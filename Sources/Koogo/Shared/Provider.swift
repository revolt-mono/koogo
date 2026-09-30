enum Provider: String, CaseIterable, Sendable, Encodable, CodingKeyRepresentable {
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
}
