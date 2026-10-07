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

    /// The tool's configuration directory under the given user home.
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

    func ownsProcess(at executablePath: String) -> Bool {
        let executable = URL(filePath: executablePath)
        let name = executable.lastPathComponent
        return switch self {
        case .codex: name == "codex"
        case .claude: name.wholeMatch(of: /\d+\.\d+\.\d+/) != nil && executable.pathComponents.contains("claude")
        case .piAgent: false
        case .grok: name.hasPrefix("grok")
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
