import AppKit
import SwiftUI

/// A popover toggle treats each press as an independent click, not a double/triple-click gesture.
/// Leave the Button, presentation binding, and animation ownership entirely with SwiftUI.
struct PopoverClickBoundary: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.startMonitoring(view)
        return view
    }

    func updateNSView(_: NSView, context _: Context) {}

    static func dismantleNSView(_: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    @MainActor
    final class Coordinator {
        private var eventMonitor: Any?

        func startMonitoring(_ view: NSView) {
            eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .leftMouseUp],
                handler: { [weak view] event in
                    guard let view else { return event }
                    return Self.independentClick(event, in: view)
                }
            )
        }

        func stopMonitoring() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
        }

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
}
