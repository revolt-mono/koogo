import SwiftUI

struct CheckForUpdatesRow: View {
  var body: some View {
    LabeledContent("Check for Updates") {
      Button("Check Now", action: updateModel.checkForUpdates)
    }
  }

  @Environment(UpdateModel.self) private var updateModel
}
