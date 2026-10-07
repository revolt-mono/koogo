import Foundation

/// How to recognize and read one kind of log file.
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
    /// Admits a matching file as a log, or returns nil when the file is not one or cannot be read.
    let open: @Sendable (_ url: URL, _ windowStart: Date) -> (any TrackedLog)?
}

struct UsageLogRoot: Sendable {
    let provider: Provider
    let url: URL
    let format: UsageLogFormat
}
