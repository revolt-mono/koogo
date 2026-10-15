import AppKit
import SwiftUI

extension View {
    /// bounded appkit tracking avoids swiftui hover hit-testing the whole window on every mouse move, even after removal.
    func onPointerHover(perform action: @escaping (Bool) -> Void) -> some View {
        background(PointerTracker(options: []) { action($0 != .ended) }.allowsHitTesting(false))
    }

    /// reports hover points in the view's local coordinates.
    func onContinuousPointerHover(perform action: @escaping (HoverPhase) -> Void) -> some View {
        background(PointerTracker(options: .mouseMoved, action: action).allowsHitTesting(false))
    }
}

private struct PointerTracker: NSViewRepresentable {
    let options: NSTrackingArea.Options
    let action: (HoverPhase) -> Void

    func makeNSView(context _: Context) -> TrackingView {
        TrackingView(options: options.union([.mouseEnteredAndExited, .activeAlways, .inVisibleRect]), action: action)
    }

    func updateNSView(_ view: TrackingView, context _: Context) {
        view.action = action
    }

    final class TrackingView: NSView {
        private let options: NSTrackingArea.Options
        var action: (HoverPhase) -> Void
        private var isInside = false

        init(options: NSTrackingArea.Options, action: @escaping (HoverPhase) -> Void) {
            self.options = options
            self.action = action
            super.init(frame: .zero)
            clipsToBounds = true
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is unavailable")
        }

        override var isFlipped: Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(NSTrackingArea(rect: .zero, options: options, owner: self))

            guard let window else { return exit() }
            let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            if visibleRect.contains(point) {
                enter(at: point)
            } else {
                exit()
            }
        }

        override func mouseEntered(with event: NSEvent) {
            enter(at: convert(event.locationInWindow, from: nil))
        }

        override func mouseMoved(with event: NSEvent) {
            guard isInside else { return }
            action(.active(convert(event.locationInWindow, from: nil)))
        }

        override func mouseExited(with _: NSEvent) {
            exit()
        }

        private func enter(at point: CGPoint) {
            guard !isInside else { return }
            isInside = true
            action(.active(point))
        }

        private func exit() {
            guard isInside else { return }
            isInside = false
            action(.ended)
        }
    }
}

extension View {
    /// appkit tooltip rectangles track entry and exit; swiftui help hit-tests the whole window on every mouse move.
    func tooltip(_ text: String) -> some View {
        background(ToolTipRect(text: text).allowsHitTesting(false))
            .accessibilityHint(text)
    }
}

private struct ToolTipRect: NSViewRepresentable {
    let text: String

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        view.toolTip = text
        return view
    }

    func updateNSView(_ view: NSView, context _: Context) {
        view.toolTip = text
    }
}
