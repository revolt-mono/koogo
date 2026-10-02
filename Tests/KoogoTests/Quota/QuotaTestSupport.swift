import Synchronization

@testable import Koogo

extension [QuotaWindow] {
    subscript(title: String) -> QuotaWindow? {
        first { $0.title == title }
    }
}

extension QuotaReading {
    func get() throws -> QuotaSnapshot {
        switch self {
        case .available(let snapshot): snapshot
        case .unavailable(let reason): throw reason
        }
    }
}

extension QuotaSnapshot {
    static func stub(_ usedPercent: Int = 50) -> QuotaSnapshot {
        QuotaSnapshot(windows: [
            QuotaWindow(title: "Session", usedPercent: Double(usedPercent), resetsAt: nil)
        ])!
    }
}

final class ScriptedQuotaSource: QuotaSource {
    let loads = Mutex(0)
    private let readings: Mutex<[QuotaReading]>

    init(_ readings: [QuotaReading]) {
        self.readings = Mutex(readings)
    }

    func load() async -> QuotaReading {
        loads.withLock { $0 += 1 }
        return readings.withLock { $0.removeFirst() }
    }
}

/// A quota model whose Codex source finds no binary; scripted Claude and Grok sources drive the tests.
@MainActor
func makeQuotaModel(
    claude: any QuotaSource = ScriptedQuotaSource([]),
    grok: any QuotaSource = ScriptedQuotaSource([])
) -> QuotaModel {
    QuotaModel(codex: CodexQuotaSource(executableCandidates: []), claude: claude, grok: grok)
}
