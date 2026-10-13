import SwiftUI

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
            .environment(models.mouse)
    }
}
