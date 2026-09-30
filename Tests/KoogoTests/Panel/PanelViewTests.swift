import AppKit
import SwiftUI
import XCTest

@testable import Koogo

final class PanelViewTests: XCTestCase {
    @MainActor
    func testQuotaPreferencesGateProvidersIndependentlyWithoutDisablingUsage() async throws {
        let workspace = try UsageTestWorkspace(root: makeTemporaryDirectory())
        try workspace.write(codexLog(input: 700, output: 300), to: workspace.codexSessions.appending(path: "log.jsonl"))
        let defaults = try makeIsolatedDefaults()
        let update = UpdateModel()
        let reminder = BreakReminderModel(notifications: BreakReminderTestNotifications(), defaults: defaults)
        let inbox = InboxModel(defaults: defaults)

        let choices: [Set<Provider>?] = [
            nil, [.claude, .grok], [.codex, .grok], [.codex, .claude], [.codex, .claude, .grok], [],
        ]
        for disabled in choices {
            defaults.set(disabled.map { $0.map(\.rawValue).sorted() }, forKey: "quota-disabled-providers")
            let usage = UsageModel(
                usageService: UsageService(locations: workspace.locations, calendar: usageTestCalendar),
                defaults: defaults,
                now: { usageTestTimestamp }
            )
            let codexSource = CodexQuotaSource(executableCandidates: [])
            let quota = QuotaModel(
                sources: [
                    .codex: codexSource,
                    .claude: ClaudeQuotaSource(executableCandidates: []),
                    .grok: GrokQuotaSource(executableCandidates: []),
                ],
                defaults: defaults
            )
            let codexReset = CodexQuotaResetModel(quotaModel: quota, source: codexSource)
            let host = NSHostingView(
                rootView: PanelView()
                    .defaultAppStorage(defaults)
                    .environment(usage)
                    .environment(quota)
                    .environment(codexReset)
                    .environment(update)
                    .environment(reminder)
                    .environment(inbox)
            )
            host.layoutSubtreeIfNeeded()
            try await waitUntil { usage.snapshot != nil }
            XCTAssertEqual(usage.snapshot?.providers[.codex]?.today.processedTokens, 1_000)

            try await waitUntil { quota.providers.allSatisfy { !quota.isBusy($0) } }
            for provider in quota.providers {
                let isEnabled = !(disabled ?? []).contains(provider)
                XCTAssertEqual(quota.states[provider], isEnabled ? .unavailable(.binaryNotFound) : nil, "\(provider)")
            }
            withExtendedLifetime(host) {}
        }
    }
}
