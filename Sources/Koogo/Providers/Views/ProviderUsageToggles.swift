import SwiftUI
import UniformTypeIdentifiers

struct ProviderUsageToggles: View {
  var body: some View {
    @Bindable var preferences = preferences
    ForEach(preferences.order, id: \.self) { provider in
      HStack(spacing: 10) {
        Image(systemName: "square.grid.4x3.fill")
          .font(.system(size: 9))
          .foregroundStyle(.tertiary)
          .accessibilityHidden(true)

        Toggle(provider.title, isOn: $preferences[usage: provider])
      }
      .contentShape(.rect)
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
        delegate: ProviderReorderDrop(provider: provider, dragged: $dragged, preferences: preferences),
      )
      .motionAnimation(.smooth(duration: 0.25), value: preferences.order)
    }
  }

  /// `script/build.sh` declares this type in the bundle's info plist.
  private static let dragType = UTType(exportedAs: "com.revolt.koogo.provider")

  @Environment(ProviderPreferences.self) private var preferences
  @State private var dragged: Provider?
}

private struct ProviderReorderDrop: DropDelegate {
  let provider: Provider
  @Binding var dragged: Provider?

  let preferences: ProviderPreferences

  func dropEntered(info _: DropInfo) {
    guard let dragged else { return }
    preferences.move(dragged, to: provider)
  }

  func dropUpdated(info _: DropInfo) -> DropProposal? {
    DropProposal(operation: .move)
  }

  func performDrop(info _: DropInfo) -> Bool {
    dragged = nil
    return true
  }
}
