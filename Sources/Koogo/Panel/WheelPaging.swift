import AppKit

/// macos converts shift plus a vertical wheel notch into a horizontal notch before dispatch.
enum WheelPaging: Equatable {
    case step(Int)
    case pass
    case drop

    init(_ event: NSEvent) {
        guard event.phase.isEmpty, event.momentumPhase.isEmpty else {
            self = .pass
            return
        }
        self.init(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY)
    }

    init(deltaX: CGFloat, deltaY: CGFloat) {
        switch (deltaX, deltaY) {
        case (0, _): self = .pass
        case (_, 0): self = .step(deltaX < 0 ? 1 : -1)
        default: self = .drop
        }
    }
}
