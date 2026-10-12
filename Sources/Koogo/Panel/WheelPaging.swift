import AppKit

/// What the pager does with a scroll event. A trackpad scroll carries phases and pages by itself. A wheel click lands between pages unless the pager steps it: a sideways click steps, a vertical one goes to the page, and a tilted one is dropped. The system turns shift plus a vertical click sideways before it arrives.
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
