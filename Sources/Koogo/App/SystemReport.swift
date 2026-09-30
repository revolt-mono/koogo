import Foundation

struct SystemReport: Encodable {
    private struct QuotaOutcome: Encodable {
        let result: Result<QuotaSnapshot, QuotaUnavailability>

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
    private let quota: [Provider: QuotaOutcome]

    static func generate(
        usageService: UsageService = UsageService(),
        quotaSources: [Provider: any QuotaSource] = Provider.quotaSources,
        at date: Date = .now
    ) async throws -> Data {
        async let quota = withTaskGroup(of: (Provider, QuotaOutcome).self) { group in
            for (provider, source) in quotaSources {
                group.addTask { (provider, QuotaOutcome(result: await source.load())) }
            }
            return await group.reduce(into: [:]) { quota, outcome in quota[outcome.0] = outcome.1 }
        }
        let usage = await usageService.refresh(at: date)
        let report = SystemReport(generatedAt: date, usage: usage, quota: await quota)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }
}
