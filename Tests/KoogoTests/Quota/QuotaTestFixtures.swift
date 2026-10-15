import Darwin
import Foundation
import Synchronization
import XCTest

@testable import Koogo

extension [QuotaWindow] {
    subscript(title: String) -> QuotaWindow? {
        first { $0.title == title }
    }
}

extension QuotaUnavailability: Error {}

extension QuotaReading {
    func get() throws -> QuotaSnapshot {
        switch self {
        case .available(let snapshot): snapshot
        case .unavailable(let reason): throw reason
        }
    }
}

extension QuotaSnapshot.ResetCredit {
    static let stub = QuotaSnapshot.ResetCredit(
        id: "credit-a",
        title: "Usage reset",
        expiresAt: Date(timeIntervalSince1970: 4_102_444_800)
    )
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

final class ScriptedCodexResetSource: CodexQuotaResetSource {
    let loads = Mutex(0)
    let consumed = Mutex<[CodexQuotaResetAttempt]>([])
    private let readings: Mutex<[QuotaReading]>
    private let consumes: Mutex<[CodexQuotaResetResult]>

    init(readings: [QuotaReading] = [], consumes: [CodexQuotaResetResult] = []) {
        self.readings = Mutex(readings)
        self.consumes = Mutex(consumes)
    }

    func load() async -> QuotaReading {
        loads.withLock { $0 += 1 }
        return readings.withLock { $0.removeFirst() }
    }

    func consume(_ attempt: CodexQuotaResetAttempt) async -> CodexQuotaResetResult {
        consumed.withLock { $0.append(attempt) }
        return consumes.withLock { $0.removeFirst() }
    }
}

extension QuotaSources {
    static var missingExecutables: Self {
        QuotaSources(
            codex: CodexQuotaSource(executableCandidates: []),
            claude: ClaudeQuotaSource(executableCandidates: []),
            grok: GrokQuotaSource(executableCandidates: [])
        )
    }
}

@MainActor
func makeQuotaModel(
    codex: any CodexQuotaResetSource = ScriptedCodexResetSource(),
    claude: any QuotaSource = ScriptedQuotaSource([]),
    grok: any QuotaSource = ScriptedQuotaSource([]),
    now: @escaping @MainActor () -> ContinuousClock.Instant = { .now }
) -> QuotaModel {
    QuotaModel(sources: QuotaSources(codex: codex, claude: claude, grok: grok), now: now)
}

func waitForExit(
    pidIn marker: URL,
    file: StaticString = #filePath,
    line: UInt = #line
) async throws {
    let text = try String(contentsOf: marker, encoding: .utf8).trimmingCharacters(in: .newlines)
    let pid = try XCTUnwrap(pid_t(text), file: file, line: line)
    try await waitUntil(timeout: .seconds(3), file: file, line: line) { kill(pid, 0) == -1 && errno == ESRCH }
}

protocol ScriptedToolWorkspace {
    var root: URL { get }
}

extension ScriptedToolWorkspace {
    var requestsFile: URL { root.appending(path: "requests.jsonl") }
    var argumentsFile: URL { root.appending(path: "arguments") }

    var prologue: String {
        """
        #!/bin/sh
        printf '%s\\n' "$@" > '\(argumentsFile.path)'
        """
    }
}

func jsonObjects(in file: URL) throws -> [[String: Any]] {
    try String(contentsOf: file, encoding: .utf8).split(separator: "\n").map { line in
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    }
}
