import Foundation

struct UsageEventIndex: Sendable {
    private var codex: [UsageEvent.CodexID: UsageRecord] = [:]
    private var claude: [UsageEvent.ClaudeID: (usage: UsageRecord, revision: UsageEvent.ClaudeRevision)] = [:]
    private var piAgent: [String: UsageRecord] = [:]
    private var unpricedModels: [String: Date] = [:]

    var unpricedModelIDs: [String] { Array(unpricedModels.keys) }

    var values: [UsageEvent] {
        var events: [UsageEvent] = []
        events.reserveCapacity(codex.count + claude.count + piAgent.count)
        events.append(contentsOf: codex.lazy.map { .codex(id: $0.key, usage: $0.value) })
        events.append(
            contentsOf: claude.lazy.map {
                .claude(id: $0.key, usage: $0.value.usage, revision: $0.value.revision)
            }
        )
        events.append(contentsOf: piAgent.lazy.map { .piAgent(entryID: $0.key, usage: $0.value) })
        return events
    }

    mutating func insert(_ event: UsageEvent) {
        switch event {
        case .codex(let id, let usage):
            guard codex[id] == nil else {
                return
            }
            codex[id] = usage
        case .claude(let id, let usage, let revision):
            if let existing = claude[id], !revision.isPreferred(over: existing.revision) {
                return
            }
            claude[id] = (usage, revision)
        case .piAgent(let entryID, let usage):
            guard piAgent[entryID] == nil else {
                return
            }
            piAgent[entryID] = usage
        }
    }

    mutating func recordUnpricedModel(_ id: String, at timestamp: Date) {
        unpricedModels[id] = max(unpricedModels[id] ?? .distantPast, timestamp)
    }

    mutating func merge(_ other: Self) {
        codex.merge(other.codex) { current, _ in current }
        claude.merge(other.claude) { current, candidate in
            candidate.revision.isPreferred(over: current.revision) ? candidate : current
        }
        piAgent.merge(other.piAgent) { current, _ in current }
        unpricedModels.merge(other.unpricedModels) { current, candidate in max(current, candidate) }
    }

    mutating func discard(before historyStart: Date) {
        codex = codex.filter { $0.value.timestamp >= historyStart }
        claude = claude.filter { $0.value.usage.timestamp >= historyStart }
        piAgent = piAgent.filter { $0.value.timestamp >= historyStart }
        unpricedModels = unpricedModels.filter { $0.value >= historyStart }
    }
}
