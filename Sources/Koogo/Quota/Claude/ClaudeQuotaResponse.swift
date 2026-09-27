import Foundation

/// One `stream-json` event from `claude -p /usage`. Only the assistant's structured usage report
/// is authoritative; result text is never scraped.
struct ClaudeQuotaResponse: Decodable {
    struct Report: Decodable {
        let rateLimits: RateLimits?

        func snapshot() throws -> ClaudeQuotaSnapshot? {
            var session: QuotaWindow?
            var weekly: QuotaWindow?
            var models: [String: QuotaWindow] = [:]
            for limit in rateLimits?.limits ?? [] where limit.scope?.surface == nil {
                switch limit.kind {
                case "session" where limit.scope == nil:
                    session = try limit.window()
                case "weekly_all" where limit.scope == nil:
                    weekly = try limit.window()
                case "weekly_scoped":
                    guard let title = limit.scope?.model?.displayName.trimmingCharacters(in: .whitespaces),
                        !title.isEmpty
                    else { break }
                    models[title] = try limit.window()
                default:
                    break
                }
            }
            return ClaudeQuotaSnapshot(
                session: session,
                weekly: weekly,
                models: models.sorted { $0.key < $1.key }.map {
                    ClaudeQuotaSnapshot.Model(title: $0.key, weekly: $0.value)
                }
            )
        }
    }

    struct RateLimits: Decodable {
        let limits: [Limit]?
    }

    struct Limit: Decodable {
        let kind: String
        let percent: Double?
        let resetsAt: String?
        let scope: Scope?

        func window() throws -> QuotaWindow {
            guard let percent, percent.isFinite else { throw ClaudeQuotaUnavailability.sessionFailed }
            let resetsAt = try resetsAt.map { text in
                guard
                    let date = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
                        ?? (try? Date.ISO8601FormatStyle().parse(text))
                else { throw ClaudeQuotaUnavailability.sessionFailed }
                return date
            }
            return QuotaWindow(usedPercent: Int(min(max(percent, 0), 100)), resetsAt: resetsAt)
        }
    }

    struct Scope: Decodable {
        let model: Model?
        /// A surface-scoped limit cannot be presented as an account or model-wide limit.
        let surface: String?
    }

    struct Model: Decodable {
        let displayName: String
    }

    let type: String
    let subtype: String?
    let isError: Bool?
    let usageReport: Report?

    /// Nil when the CLI succeeded but reported no usable limits.
    static func snapshot(from output: Data) throws -> ClaudeQuotaSnapshot? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        var report: Report?
        var succeeded = false
        for line in output.split(separator: 0x0A) {
            let event = try decoder.decode(Self.self, from: Data(line))
            switch event.type {
            case "assistant":
                report = event.usageReport ?? report
            case "result":
                guard event.subtype == "success", event.isError == false else {
                    throw ClaudeQuotaUnavailability.sessionFailed
                }
                succeeded = true
            default:
                break
            }
        }
        guard succeeded, let report else { throw ClaudeQuotaUnavailability.sessionFailed }
        return try report.snapshot()
    }
}
