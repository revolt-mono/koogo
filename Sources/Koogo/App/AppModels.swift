import SwiftUI

/// Every model the scenes share, injected together so a view cannot run without one.
struct AppModels {
    let preferences: ProviderPreferences
    let usage: UsageModel
    let quota: QuotaModel
    let codexReset: CodexQuotaResetModel
    let update: UpdateModel
    let breakReminder: BreakReminderModel
    let inbox: InboxModel
    let activity: ActivityModel
}

extension View {
    func environment(_ models: AppModels) -> some View {
        environment(models.preferences)
            .environment(models.usage)
            .environment(models.quota)
            .environment(models.codexReset)
            .environment(models.update)
            .environment(models.breakReminder)
            .environment(models.inbox)
            .environment(models.activity)
    }
}
