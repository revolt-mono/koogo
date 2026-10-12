import AppKit
import SwiftUI

extension NSEvent {
    /// A multi-click on the view counts as a fresh single click, so each press toggles its popover.
    @MainActor
    func independentClick(in view: NSView) -> NSEvent {
        guard clickCount > 1, isInside(view) else { return self }
        return NSEvent.mouseEvent(
            with: type,
            location: locationInWindow,
            modifierFlags: modifierFlags,
            timestamp: timestamp,
            windowNumber: windowNumber,
            context: nil,
            eventNumber: eventNumber,
            clickCount: 1,
            pressure: pressure
        ) ?? self
    }
}

struct PanelDisclosure<Label: View, Content: View>: View {
    @State private var isPresented = false

    @ViewBuilder let label: (_ isPresented: Bool) -> Label
    @ViewBuilder let content: () -> Content

    init(
        @ViewBuilder label: @escaping (_ isPresented: Bool) -> Label,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.label = label
        self.content = content
    }

    init(@ViewBuilder label: @escaping () -> Label, @ViewBuilder content: @escaping () -> Content) {
        self.init(label: { _ in label() }, content: content)
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            label(isPresented)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isPresented ? "Expanded" : "Collapsed")
        .background {
            LocalEventMonitor(events: [.leftMouseDown, .leftMouseUp]) { event, view in
                event.independentClick(in: view)
            }
            .allowsHitTesting(false)
        }
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            content()
                .font(.system(size: 11, weight: .medium))
                .frame(width: 264)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
        }
        .onScrollVisibilityChange(threshold: 0.1) { isVisible in
            if !isVisible {
                isPresented = false
            }
        }
        .onDisappear {
            isPresented = false
        }
    }
}
