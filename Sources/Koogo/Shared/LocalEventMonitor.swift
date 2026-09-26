import AppKit
import SwiftUI

/// Passes local events of the given types, with the monitor's own view, to `handler`; the handler returns
/// the event to dispatch, or nil to consume it. The monitor lives exactly as long as the view.
struct LocalEventMonitor: NSViewRepresentable {
    let events: NSEvent.EventTypeMask
    let handler: @MainActor (NSEvent, NSView) -> NSEvent?

    func makeCoordinator() -> Coordinator {
        Coordinator(handler: handler)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let coordinator = context.coordinator
        coordinator.monitor = NSEvent.addLocalMonitorForEvents(
            matching: events,
            handler: { [weak view] event in
                guard let view else { return event }
                return coordinator.handler(event, view)
            }
        )
        return view
    }

    func updateNSView(_: NSView, context: Context) {
        context.coordinator.handler = handler
    }

    static func dismantleNSView(_: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor {
            NSEvent.removeMonitor(monitor)
            coordinator.monitor = nil
        }
    }

    @MainActor
    final class Coordinator {
        var handler: @MainActor (NSEvent, NSView) -> NSEvent?
        var monitor: Any?

        init(handler: @escaping @MainActor (NSEvent, NSView) -> NSEvent?) {
            self.handler = handler
        }
    }
}
