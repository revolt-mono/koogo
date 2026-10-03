import Foundation

struct UsageLogRoot: Sendable {
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

    let provider: Provider
    let url: URL
    let match: Match
    /// Admits a matching file as a log, or returns nil when the file is not one or cannot be read.
    let open: @Sendable (_ url: URL, _ windowStart: Date) -> (any TrackedLog)?
}
