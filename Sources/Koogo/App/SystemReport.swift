import Foundation

struct SystemReport: Encodable {
    private let generatedAt: Date
    private let usage: UsageReport
    private let quota: EnumMap<QuotaProvider, QuotaReading>

    static func generate(
        pipeline: UsagePipeline = UsagePipeline(),
        quotaSources: QuotaSources = .production,
        at date: Date = .now
    ) async throws -> Data {
        async let quota = readEveryQuota(from: quotaSources)
        let usage = await pipeline.run(at: date, providers: Provider.allCases)
        let report = SystemReport(generatedAt: date, usage: usage, quota: await quota)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }

    private static func readEveryQuota(from sources: QuotaSources) async -> EnumMap<QuotaProvider, QuotaReading> {
        await withTaskGroup(of: (QuotaProvider, QuotaReading).self) { group in
            for provider in QuotaProvider.allCases {
                group.addTask { (provider, await sources[provider].load()) }
            }
            var readings: [QuotaProvider: QuotaReading] = [:]
            for await (provider, reading) in group {
                readings[provider] = reading
            }
            return EnumMap { readings[$0]! }
        }
    }
}
