import Foundation

/// Headless snapshot of the whole system for `Koogo --report`: runs the full
/// usage pipeline and a quota fetch, then encodes the outcome as JSON. This is
/// the canonical way to verify behavior end to end without the menu bar UI.
struct SystemReport: Encodable {
    private let generatedAt: Date
    private let usage: UsageReport
    private let quota: Result<CodexQuotaSnapshot, CodexQuotaUnavailability>

    static func generate(
        locations: UsageLocations = .standard,
        quotaService: CodexQuotaService = CodexQuotaService(),
        at date: Date = .now
    ) async throws -> Data {
        async let quota = quotaService.fetch()
        let usage = await UsageService(locations: locations).refresh(at: date)
        let report = SystemReport(generatedAt: date, usage: usage, quota: await quota)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(usage, forKey: .usage)
        var quotaContainer = container.nestedContainer(keyedBy: QuotaKeys.self, forKey: .quota)
        switch quota {
        case .success(let snapshot):
            try quotaContainer.encode("available", forKey: .state)
            try quotaContainer.encode(snapshot, forKey: .snapshot)
        case .failure(let reason):
            try quotaContainer.encode("unavailable", forKey: .state)
            try quotaContainer.encode(reason, forKey: .reason)
        }
    }

    private enum CodingKeys: CodingKey {
        case generatedAt
        case usage
        case quota
    }

    private enum QuotaKeys: CodingKey {
        case state
        case reason
        case snapshot
    }
}
