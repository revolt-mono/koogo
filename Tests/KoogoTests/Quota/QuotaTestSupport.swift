import Synchronization

@testable import Koogo

extension [QuotaWindow] {
    subscript(title: String) -> QuotaWindow? {
        first { $0.title == title }
    }
}

extension QuotaSnapshot {
    static func stub(_ remainingPercent: Int = 50) -> QuotaSnapshot {
        QuotaSnapshot(account: [
            QuotaWindow(title: "Session", usedPercent: Double(100 - remainingPercent), resetsAt: nil)
        ])!
    }
}

/// Answers each load from a queue, in order, and counts them.
final class ScriptedQuotaSource: QuotaSource {
    let loads = Mutex(0)
    private let results: Mutex<[Result<QuotaSnapshot, QuotaUnavailability>]>

    init(_ results: [Result<QuotaSnapshot, QuotaUnavailability>]) {
        self.results = Mutex(results)
    }

    func load() async -> Result<QuotaSnapshot, QuotaUnavailability> {
        loads.withLock { $0 += 1 }
        return results.withLock { $0.removeFirst() }
    }
}
