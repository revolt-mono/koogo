import Foundation

struct DroppedInput: Sendable {
  private(set) var malformedLines = 0

  var unpricedModels: some Collection<ModelID> {
    unpricedModelLastUse.keys
  }

  mutating func noteMalformedLine() {
    malformedLines += 1
  }

  mutating func noteUnpricedModel(_ model: ModelID, at timestamp: UsageTimestamp) {
    unpricedModelLastUse[model] = max(unpricedModelLastUse[model] ?? timestamp, timestamp)
  }

  mutating func discard(before windowStart: UsageTimestamp) {
    unpricedModelLastUse = unpricedModelLastUse.filter { $0.value >= windowStart }
  }

  private var unpricedModelLastUse = [ModelID: UsageTimestamp]()
}
