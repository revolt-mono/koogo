import Foundation

struct SystemReport: Encodable {
    private let generatedAt: Date
    private let usage: UsageReport
    private let quota: [QuotaProvider: QuotaReading]

    static func generate(
        pipeline: UsagePipeline = UsagePipeline(),
        quotaSources: EnumMap<QuotaProvider, any QuotaSource> = EnumMap(
            codex: CodexQuotaSource(),
            claude: ClaudeQuotaSource(),
            grok: GrokQuotaSource()
        ),
        at date: Date = .now
    ) async throws -> Data {
        async let quota = withTaskGroup(of: (QuotaProvider, QuotaReading).self) { group in
            for (provider, source) in quotaSources.entries {
                group.addTask { (provider, await source.load()) }
            }
            return await group.reduce(into: [:]) { readings, read in readings[read.0] = read.1 }
        }
        let usage = await pipeline.run(at: date, providers: Provider.allCases)
        let report = SystemReport(generatedAt: date, usage: usage, quota: await quota)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }
}
