import Foundation

/// Lines a log dropped: malformed ones by count, unpriced ones by model and latest timestamp.
struct LogTally: Sendable {
    private(set) var malformedLines = 0
    private var unpricedModels: [String: Date] = [:]

    var unpricedModelIDs: some Collection<String> {
        unpricedModels.keys
    }

    mutating func countMalformedLines(_ count: Int) {
        malformedLines += count
    }

    mutating func noteUnpricedModel(_ id: String, at timestamp: Date, since windowStart: Date) {
        guard timestamp >= windowStart else {
            return
        }
        unpricedModels[id] = max(unpricedModels[id] ?? .distantPast, timestamp)
    }

    mutating func discard(before windowStart: Date) {
        unpricedModels = unpricedModels.filter { $0.value >= windowStart }
    }
}
