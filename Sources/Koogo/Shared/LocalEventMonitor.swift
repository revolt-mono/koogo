import AppKit
import SwiftUI

extension NSEvent {
  @MainActor
  func isInside(_ view: NSView) -> Bool {
    guard let window = view.window, self.window === window, !view.isHiddenOrHasHiddenAncestor else {
      return false
    }
    return view.bounds.intersection(view.visibleRect).contains(view.convert(locationInWindow, from: nil))
  }
}

extension View {
  func onLocalEvent(
    _ events: NSEvent.EventTypeMask,
    perform handler: @escaping @MainActor (NSEvent, NSView) -> NSEvent?,
  ) -> some View {
    background(LocalEventMonitor(events: events, handler: handler).allowsHitTesting(false))
  }
}

private struct LocalEventMonitor: NSViewRepresentable {
  @MainActor
  final class Coordinator {
    init(handler: @escaping @MainActor (NSEvent, NSView) -> NSEvent?) {
      self.handler = handler
    }

    var handler: @MainActor (NSEvent, NSView) -> NSEvent?
    var monitor: Any?
  }

  let events: NSEvent.EventTypeMask
  let handler: @MainActor (NSEvent, NSView) -> NSEvent?

  static func dismantleNSView(_: NSView, coordinator: Coordinator) {
    if let monitor = coordinator.monitor {
      NSEvent.removeMonitor(monitor)
      coordinator.monitor = nil
    }
  }

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
      },
    )
    return view
  }

  func updateNSView(_: NSView, context: Context) {
    context.coordinator.handler = handler
  }
}
