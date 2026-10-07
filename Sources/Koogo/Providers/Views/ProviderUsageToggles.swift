import SwiftUI
import UniformTypeIdentifiers

struct ProviderUsageToggles: View {
    private static let dragType = UTType(exportedAs: "com.revolt.koogo.provider")

    @Environment(ProviderPreferences.self) private var preferences
    @State private var dragged: Provider?

    var body: some View {
        ForEach(preferences.order, id: \.self) { provider in
            HStack(spacing: 10) {
                Image(systemName: "square.grid.4x3.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)

                Toggle(
                    provider.title,
                    isOn: Binding(
                        get: { preferences.isUsageEnabled(provider) },
                        set: { preferences.setUsage($0, for: provider) }
                    )
                )
            }
            .contentShape(Rectangle())
            .onDrag {
                dragged = provider
                let item = NSItemProvider()
                item.registerDataRepresentation(for: Self.dragType, visibility: .ownProcess) { completion in
                    completion(Data(provider.rawValue.utf8), nil)
                    return nil
                }
                return item
            }
            .onDrop(
                of: [Self.dragType],
                delegate: ProviderReorderDrop(provider: provider, dragged: $dragged, preferences: preferences)
            )
            .motionAnimation(.smooth(duration: 0.25), value: preferences.order)
        }
    }
}

private struct ProviderReorderDrop: DropDelegate {
    let provider: Provider
    @Binding var dragged: Provider?
    let preferences: ProviderPreferences

    func dropEntered(info: DropInfo) {
        guard let dragged else { return }
        preferences.move(dragged, to: provider)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragged = nil
        return true
    }
}
