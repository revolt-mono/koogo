import Foundation

struct UsageLogFormat: Sendable {
  init<Parser: UsageLogParser>(
    _: Parser.Type,
    match: Match,
    admits: @escaping @Sendable (_ path: String) throws -> Bool = { _ in true },
  ) {
    self.match = match
    open = { path, metadata, windowStart in
      guard let isAdmitted = try? admits(path) else {
        return .unreadable
      }
      guard isAdmitted else {
        return .declined
      }
      let file: any LogFile =
        if path.hasSuffix(".zst") {
          CompressedFile(path, observed: metadata)
        } else {
          AppendOnlyFile(path, observed: metadata)
        }
      guard let log = ParsedLog<Parser>(file, since: windowStart) else {
        return .unreadable
      }
      return .opened(log)
    }
  }

  enum Opening: Sendable {
    case opened(any TrackedLog)
    case declined
    case unreadable
  }

  enum Match: Sendable {
    /// codex compresses rollouts a week after their last write.
    case jsonLines
    case fileName(String)

    func matches(path: String) -> Bool {
      switch self {
      case .jsonLines: path.hasSuffix(".jsonl") || path.hasSuffix(".jsonl.zst")
      case .fileName(let name): path.hasSuffix("/" + name)
      }
    }
  }

  let match: Match
  let open: @Sendable (_ path: String, _ observed: UsageFileMetadata, _ windowStart: UsageTimestamp) -> Opening

  static func jsonLines(_ parser: (some UsageLogParser).Type) -> Self {
    Self(parser, match: .jsonLines)
  }
}
