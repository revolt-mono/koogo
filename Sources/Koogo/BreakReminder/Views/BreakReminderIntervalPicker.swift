import SwiftUI

struct BreakReminderIntervalPicker: View {
    @Environment(BreakReminderModel.self) private var reminderModel
    @State private var issue: BreakReminderIssue?

    var body: some View {
        Picker(
            "Remind Me Every",
            selection: Binding(
                get: { reminderModel.countdown.interval },
                set: { interval in
                    Task {
                        issue = await reminderModel.perform(.setInterval(interval))
                    }
                }
            )
        ) {
            ForEach(BreakReminderInterval.allCases, id: \.self) { interval in
                Text("\(interval.rawValue) Minutes")
                    .tag(interval)
            }
        }
        .pickerStyle(.menu)
        .disabled(reminderModel.isBusy)
        .breakReminderIssueAlert($issue)
    }
}
