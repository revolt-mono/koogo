import Foundation

/// Headless snapshot of the whole system for `Koogo --report`: runs the full
/// usage pipeline and both quota fetches, then encodes the outcome as JSON. This is
/// the canonical way to verify behavior end to end without the menu bar UI.
struct SystemReport: Encodable {
    private struct Quota: Encodable {
        let codex: QuotaOutcome<CodexQuotaSnapshot, CodexQuotaUnavailability>
        let grok: QuotaOutcome<GrokQuotaSnapshot, GrokQuotaUnavailability>
    }

    private struct QuotaOutcome<Snapshot: Encodable, Reason: Error & Encodable>: Encodable {
        let result: Result<Snapshot, Reason>

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch result {
            case .success(let snapshot):
                try container.encode("available", forKey: .state)
                try container.encode(snapshot, forKey: .snapshot)
            case .failure(let reason):
                try container.encode("unavailable", forKey: .state)
                try container.encode(reason, forKey: .reason)
            }
        }

        private enum CodingKeys: CodingKey {
            case state
            case reason
            case snapshot
        }
    }

    private let generatedAt: Date
    private let usage: UsageReport
    private let quota: Quota

    static func generate(
        locations: UsageLocations = .standard,
        codexQuotaService: CodexQuotaService = CodexQuotaService(),
        grokQuotaService: GrokQuotaService = GrokQuotaService(),
        at date: Date = .now
    ) async throws -> Data {
        async let codexQuota = codexQuotaService.fetch()
        async let grokQuota = grokQuotaService.fetch()
        let usage = await UsageService(locations: locations).refresh(at: date)
        let report = SystemReport(
            generatedAt: date,
            usage: usage,
            quota: Quota(codex: QuotaOutcome(result: await codexQuota), grok: QuotaOutcome(result: await grokQuota))
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }
}
