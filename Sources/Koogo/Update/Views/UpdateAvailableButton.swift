import SwiftUI

struct UpdateAvailableButton: View {
    @Environment(UpdateModel.self) private var updateModel

    var body: some View {
        Button(action: updateModel.checkForUpdates) {
            Text("Update")
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .foregroundStyle(.white)
                .background(.tint, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Update available")
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
