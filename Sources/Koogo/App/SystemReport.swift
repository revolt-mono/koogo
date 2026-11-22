import Foundation

struct SystemReport: Encodable {
  static func generate(
    pipeline: UsagePipeline = UsagePipeline(),
    quotaSources: QuotaSources = .production,
    at date: Date = .now,
  ) async throws -> Data {
    async let quota = quotaSources.loadAll()
    let usage = await pipeline.run(at: date, providers: Provider.allCases)
    let report = SystemReport(generatedAt: date, usage: usage, quota: await quota)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(report)
  }

  private let generatedAt: Date
  private let usage: UsageReport
  private let quota: EnumMap<QuotaProvider, QuotaReading>
}
