import Foundation

/// Deduplicated events inside one history window. Each provider has its own
/// identity and precedence rule; every insert and merge applies them here.
struct UsageEventIndex: Sendable {
    private(set) var historyStart: Date
    private var codex: [UsageEvent.CodexID: UsageRecord] = [:]
    private var claude: [UsageEvent.ClaudeID: UsageEvent.ClaudeRevision] = [:]
    private var piAgent: [String: UsageRecord] = [:]
    private var unpricedModels: [String: Date] = [:]

    init(since historyStart: Date) {
        self.historyStart = historyStart
    }

    var counts: [UsageProvider: Int] {
        [.codex: codex.count, .claude: claude.count, .piAgent: piAgent.count]
    }

    var unpricedModelIDs: [String] {
        unpricedModels.keys.sorted()
    }

    var values: [UsageEvent] {
        codex.map { .codex(id: $0.key, usage: $0.value) }
            + claude.map { .claude(id: $0.key, revision: $0.value) }
            + piAgent.map { .piAgent(entryID: $0.key, usage: $0.value) }
    }

    mutating func insert(_ outcome: UsageLineOutcome) {
        guard outcome.timestamp >= historyStart else {
            return
        }
        switch outcome {
        case .event(.codex(let id, let usage)):
            guard codex[id] == nil else {
                return
            }
            codex[id] = usage
        case .event(.claude(let id, let revision)):
            if let existing = claude[id], !revision.isPreferred(over: existing) {
                return
            }
            claude[id] = revision
        case .event(.piAgent(let entryID, let usage)):
            guard piAgent[entryID] == nil else {
                return
            }
            piAgent[entryID] = usage
        case .unpricedModel(let id, let timestamp):
            unpricedModels[id] = max(unpricedModels[id] ?? .distantPast, timestamp)
        }
    }

    mutating func merge(_ other: Self) {
        codex.merge(other.codex) { current, _ in current }
        claude.merge(other.claude) { current, candidate in
            candidate.isPreferred(over: current) ? candidate : current
        }
        piAgent.merge(other.piAgent) { current, _ in current }
        unpricedModels.merge(other.unpricedModels) { current, candidate in max(current, candidate) }
    }

    mutating func discard(before historyStart: Date) {
        self.historyStart = historyStart
        codex = codex.filter { $0.value.timestamp >= historyStart }
        claude = claude.filter { $0.value.usage.timestamp >= historyStart }
        piAgent = piAgent.filter { $0.value.timestamp >= historyStart }
        unpricedModels = unpricedModels.filter { $0.value >= historyStart }
    }
}
