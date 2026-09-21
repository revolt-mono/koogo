import SwiftUI

struct BreakReminderIntervalPicker: View {
    @Environment(BreakReminderModel.self) private var reminderModel

    var body: some View {
        Picker(
            "Remind Me Every",
            selection: Binding(
                get: { reminderModel.interval },
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
        }
        .pickerStyle(.menu)
        .disabled(reminderModel.isScheduling)
    }
}
