import AppKit

/// macos converts shift plus a vertical wheel notch into a horizontal notch before dispatch.
enum WheelPaging: Equatable {
    case step(Int)
    case pass
    case drop

    init(_ event: NSEvent) {
        guard !event.hasPreciseScrollingDeltas, event.phase.isEmpty, event.momentumPhase.isEmpty else {
            self = .pass
            return
        }
        switch (event.scrollingDeltaX, event.scrollingDeltaY) {
        case (0, _): self = .pass
        case (let deltaX, 0): self = .step(deltaX < 0 ? 1 : -1)
        default: self = .drop
        }
    }
}
