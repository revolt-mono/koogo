import SwiftUI

struct BreakReminderIntervalPicker: View {
  var body: some View {
    Picker(selection: Binding(get: { reminderModel.countdown.interval }, set: setInterval)) {
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

  @Environment(BreakReminderModel.self) private var reminderModel

  private func setInterval(_ interval: BreakReminderInterval) {
    Task {
      await reminderModel.perform(.setInterval(interval))
    }
  }
}
