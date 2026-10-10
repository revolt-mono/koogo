import AppKit
import SwiftUI

@MainActor
enum PopoverClickBoundary {
    static func independentClick(_ event: NSEvent, in view: NSView) -> NSEvent {
        guard event.clickCount > 1, let window = view.window, event.window === window,
            !view.isHiddenOrHasHiddenAncestor,
            view.bounds.intersection(view.visibleRect).contains(view.convert(event.locationInWindow, from: nil))
        else { return event }
        return NSEvent.mouseEvent(
            with: event.type,
            location: event.locationInWindow,
            modifierFlags: event.modifierFlags,
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            eventNumber: event.eventNumber,
            clickCount: 1,
            pressure: event.pressure
        ) ?? event
    }
}

private struct PanelPopover<PopoverContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let popoverContent: () -> PopoverContent

    func body(content: Content) -> some View {
        content
            .accessibilityValue(isPresented ? "Expanded" : "Collapsed")
            .background {
                LocalEventMonitor(events: [.leftMouseDown, .leftMouseUp]) { event, view in
                    PopoverClickBoundary.independentClick(event, in: view)
                }
                .allowsHitTesting(false)
            }
            .popover(isPresented: $isPresented, arrowEdge: .trailing, content: popoverContent)
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
        .panelPopover(isPresented: $isPresented, content: content)
    }
}

extension View {
    func panelPopover<PopoverContent: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> PopoverContent
    ) -> some View {
        modifier(PanelPopover(isPresented: isPresented, popoverContent: content))
    }
}
