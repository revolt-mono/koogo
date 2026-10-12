import SwiftUI

struct UpdateAvailableButton: View {
    @Environment(UpdateModel.self) private var updateModel

    var body: some View {
        Button(action: updateModel.checkForUpdates) {
            Text("Update")
                .capsuleBadge(.tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Update available")
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
