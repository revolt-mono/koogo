import Foundation

struct LogTally: Sendable {
    private(set) var malformedLines = 0
    private var unpricedModels: [ModelID: Date] = [:]

    var unpricedModelIDs: some Collection<ModelID> {
        unpricedModels.keys
    }

    mutating func noteMalformedLine() {
        malformedLines += 1
    }

    mutating func noteUnpricedModel(_ id: ModelID, at timestamp: Date, since windowStart: Date) {
        guard timestamp >= windowStart else {
            return
        }
        unpricedModels[id] = max(unpricedModels[id] ?? .distantPast, timestamp)
    }

    mutating func discard(before windowStart: Date) {
        unpricedModels = unpricedModels.filter { $0.value >= windowStart }
    }
}
