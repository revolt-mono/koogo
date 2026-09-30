import AppKit
import SwiftUI

extension EnvironmentValues {
    @Entry var isSelectedPanelPage = true
}

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
    @Environment(\.isSelectedPanelPage) private var isSelectedPanelPage
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
            .onChange(of: isSelectedPanelPage) {
                if !isSelectedPanelPage {
                    isPresented = false
                }
            }
            .onDisappear {
                isPresented = false
            }
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
