import AppKit
import SwiftUI

/// Every model the app runs, built from one set of outside dependencies so no model can pair with another's. Construction has no launch effects; `KoogoApp` starts what needs starting.
@MainActor
struct AppModels {
    let preferences: ProviderPreferences
    let usage: UsageModel
    let quota: QuotaModel
    let codexReset: CodexQuotaResetModel
    let update: UpdateModel
    let breakReminder: BreakReminderModel
    let inbox: InboxModel
    let activity: ActivityModel
    let mouse: MouseModel
    let keepAwake: KeepAwakeModel

    init(
        defaults: UserDefaults = .standard,
        pipeline: UsagePipeline = UsagePipeline(),
        quotaSources: QuotaSources = .production,
        breakNotifications: any BreakReminderNotifications = BreakReminderNotificationCenter(),
        activitySample: @escaping @Sendable () async throws -> ActivitySample = ActivitySampler().sample,
        isInstalled: (String) -> Bool = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil },
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        preferences = ProviderPreferences(defaults: defaults)
        usage = UsageModel(pipeline: pipeline, now: now)
        quota = QuotaModel(sources: quotaSources)
        codexReset = CodexQuotaResetModel(quota: quota, now: now)
        update = UpdateModel()
        breakReminder = BreakReminderModel(notifications: breakNotifications, defaults: defaults, now: now)
        inbox = InboxModel(defaults: defaults)
        activity = ActivityModel(sample: activitySample)
        mouse = MouseModel(defaults: defaults, isInstalled: isInstalled)
        keepAwake = KeepAwakeModel(defaults: defaults)
    }
}

extension View {
    /// What every scene root gets: the models, the rounded face, and the display locale that `Text(_:format:)` reads.
    func sceneRoot(_ models: AppModels) -> some View {
        environment(models.preferences)
            .environment(models.usage)
            .environment(models.quota)
            .environment(models.codexReset)
            .environment(models.update)
            .environment(models.breakReminder)
            .environment(models.inbox)
            .environment(models.activity)
            .environment(models.mouse)
            .environment(models.keepAwake)
            .fontDesign(.rounded)
            .environment(\.locale, .display)
    }
}
