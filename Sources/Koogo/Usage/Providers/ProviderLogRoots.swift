import Foundation

extension Provider {
  func logRoots(under root: URL) -> [UsageLogRoot] {
    let (directories, format): ([String], UsageLogFormat) =
      switch self {
      case .codex: (["sessions", "archived_sessions"], .jsonLines(CodexUsageLogParser.self))
      case .claude: (["projects"], .jsonLines(ClaudeUsageLogParser.self))
      case .piAgent: (["sessions"], .jsonLines(PiUsageLogParser.self))
      case .grok: (["sessions"], .grokSessionUpdates)
      }
    let home = home(under: root)
    return directories.map {
      UsageLogRoot(provider: self, path: home.appending(path: $0, directoryHint: .isDirectory).path, format: format)
    }
  }
}
