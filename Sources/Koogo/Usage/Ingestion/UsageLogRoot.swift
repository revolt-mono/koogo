import Foundation

struct UsageLogFormat: Sendable {
    enum Match: Sendable {
        /// plain or zstd-compressed; codex compresses rollouts a week after their last write.
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
    let open: @Sendable (_ path: String, _ observed: UsageFileMetadata, _ windowStart: Date) -> (any TrackedLog)?

    static func jsonLines<Parser: UsageLogParser>(_: Parser.Type) -> Self {
        Self(match: .jsonLines) { path, metadata, windowStart in
            ParsedLog<Parser>(
                path.hasSuffix(".zst")
                    ? CompressedFile(path, observed: metadata) : AppendOnlyFile(path, observed: metadata),
                since: windowStart
            )
        }
    }
}

struct UsageLogRoot: Sendable {
    let provider: Provider
    let path: String
    let format: UsageLogFormat
}
