import Foundation

struct UsageLogFormat: Sendable {
    enum Match: Sendable {
        case fileExtension(String)
        case fileName(String)

        func matches(path: String) -> Bool {
            switch self {
            case .fileExtension(let suffix): path.hasSuffix(suffix)
            case .fileName(let name): path.hasSuffix("/" + name)
            }
        }
    }

    let match: Match
    let open: @Sendable (_ path: String, _ observed: UsageFileMetadata, _ windowStart: Date) -> (any TrackedLog)?

    static func jsonLines<Parser: UsageLogParser>(_: Parser.Type) -> Self {
        Self(match: .fileExtension(".jsonl")) { ParsedLog<Parser>($0, observed: $1, since: $2) }
    }
}

struct UsageLogRoot: Sendable {
    let provider: Provider
    let path: String
    let format: UsageLogFormat
}
