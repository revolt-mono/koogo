/// A coding agent this app tracks. Usage and quota both key on it.
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
