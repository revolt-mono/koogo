import SwiftUI
import UniformTypeIdentifiers

/// One toggle per provider; a disabled provider is left out of every refresh. Rows drag into a new
/// order, shifting live as the dragged row passes over them; the panel and settings both follow it.
struct UsageProviderToggles: View {
    /// A private drag type, so only a row drag from this list enters a row's drop delegate.
    private static let dragType = UTType(exportedAs: "com.revolt.koogo.provider")

    @Environment(UsageModel.self) private var usageModel
    @State private var dragged: Provider?

    var body: some View {
        ForEach(usageModel.providerOrder, id: \.self) { provider in
            HStack(spacing: 10) {
                Image(systemName: "square.grid.4x3.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)

                Toggle(
                    provider.title,
                    isOn: Binding(
                        get: { usageModel.enabledProviders.contains(provider) },
                        set: { usageModel.setEnabled($0, for: provider) }
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
                delegate: ProviderReorderDrop(provider: provider, dragged: $dragged, usageModel: usageModel)
            )
            .motionAnimation(.smooth(duration: 0.25), value: usageModel.providerOrder)
        }
    }
}

/// Moves the dragged provider into the hovered row's slot as soon as the pointer enters it, so the
/// rows reorder live; the drop itself only ends the drag.
private struct ProviderReorderDrop: DropDelegate {
    let provider: Provider
    @Binding var dragged: Provider?
    let usageModel: UsageModel

    func dropEntered(info: DropInfo) {
        guard let dragged else { return }
        usageModel.moveProvider(dragged, to: provider)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragged = nil
        return true
    }
}
