import SwiftUI

struct BreakReminderIntervalPicker: View {
    @Environment(BreakReminderModel.self) private var reminderModel

    var body: some View {
        Picker(
            selection: Binding(
                get: { reminderModel.countdown.interval },
                set: { interval in
                    Task {
                        await reminderModel.perform(.setInterval(interval))
                    }
                }
            )
        ) {
            ForEach(BreakReminderInterval.allCases, id: \.self) { interval in
                Text("\(interval.rawValue) Minutes")
                    .tag(interval)
            }
        } label: {
            Text("Remind Me Every")
            if let issue = reminderModel.issue {
                Text(issue.explanation)
            }
        }
        .pickerStyle(.menu)
        .disabled(reminderModel.isBusy)
    }
}
