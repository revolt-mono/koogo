import Foundation

/// Headless snapshot of the whole system for `Koogo --report`: runs the full
/// usage pipeline and a quota fetch, then encodes the outcome as JSON. This is
/// the canonical way to verify behavior end to end without the menu bar UI.
enum SystemReport {
    static func generate(
        locations: UsageLocations = .standard,
        quotaService: CodexQuotaService = CodexQuotaService(),
        at date: Date = .now
    ) async throws -> Data {
        async let quota = quotaService.fetch()
        let usage = await UsageService(locations: locations).refresh(at: date)
        let report = Report(
            generatedAt: date,
            usage: Report.Usage(
                logRoots: logRoots(of: locations.logs),
                ingestion: usage.ingestion,
                snapshot: usage.snapshot
            ),
            quota: Report.Quota(await quota)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }

    private static func logRoots(of logs: UsageLocations.Logs) -> [Report.LogRoot] {
        [
            (UsageProvider.codex, logs.codex.sessions),
            (.codex, logs.codex.archivedSessions),
            (.claude, logs.claudeProjects),
            (.piAgent, logs.piAgent),
        ].map { provider, url in
            Report.LogRoot(
                provider: provider,
                path: url.path,
                exists: FileManager.default.fileExists(atPath: url.path)
            )
        }
    }
}

private struct Report: Encodable {
    struct LogRoot: Encodable {
        let provider: UsageProvider
        let path: String
        let exists: Bool
    }

    struct Usage: Encodable {
        let logRoots: [LogRoot]
        let ingestion: UsageIngestionStats
        let snapshot: UsageSnapshot
    }

    struct Quota: Encodable {
        let state: String
        let reason: CodexQuotaUnavailability?
        let snapshot: CodexQuotaSnapshot?

        init(_ result: Result<CodexQuotaSnapshot, CodexQuotaUnavailability>) {
            switch result {
            case .success(let snapshot):
                state = "available"
                reason = nil
                self.snapshot = snapshot
            case .failure(let unavailability):
                state = "unavailable"
                reason = unavailability
                snapshot = nil
            }
        }
    }

    let generatedAt: Date
    let usage: Usage
    let quota: Quota
}
