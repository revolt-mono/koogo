import AppKit

enum PageStep: Equatable {
    case forward
    case backward
}

/// A scroll wheel event reduced to what paging reads. Momentum and the trackpad's tentative phases carry nothing a page step needs, so they do not parse.
struct PageScroll: Equatable {
    enum Source: Equatable {
        case wheel(shifted: Bool)
        case swipeBegan
        case swipeMoved
        case swipeEnded
    }

    let source: Source
    let deltaX: CGFloat
    let deltaY: CGFloat
}

extension PageScroll {
    init?(_ event: NSEvent) {
        guard event.momentumPhase.isEmpty else { return nil }
        switch event.phase {
        case []:
            let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
            source = .wheel(shifted: modifiers == .shift)
        case .began: source = .swipeBegan
        case .changed: source = .swipeMoved
        case .ended, .cancelled: source = .swipeEnded
        default: return nil
        }
        deltaX = event.scrollingDeltaX
        deltaY = event.scrollingDeltaY
    }
}

/// Turns the scroll stream into page steps. A wheel click steps at once when it scrolls sideways or holds shift. A trackpad swipe that sets off sideways belongs to the pager for its whole run and steps once it has travelled far enough; one that sets off vertically is left to the page under it. A class, so the swipe bookkeeping stays out of view state.
@MainActor
final class PageStepRecognizer {
    enum Verdict: Equatable {
        case step(PageStep)
        /// Part of a page swipe, with no step to take.
        case consumed
        /// Not for the pager.
        case ignored
    }

    private static let swipeDistance: CGFloat = 40

    private enum Swipe {
        case undecided
        case paging(travelled: CGFloat, stepped: Bool)
        case scrolling
    }

    private var swipe = Swipe.undecided

    func receive(_ scroll: PageScroll) -> Verdict {
        switch scroll.source {
        case .wheel(let shifted):
            let sideways = scroll.deltaY == 0 ? -scroll.deltaX : 0
            let delta = shifted && scroll.deltaY != 0 ? scroll.deltaY : sideways
            guard delta != 0 else { return .ignored }
            return .step(delta > 0 ? .forward : .backward)
        case .swipeBegan:
            swipe = .undecided
            return .ignored
        case .swipeEnded:
            defer { swipe = .undecided }
            if case .paging = swipe { return .consumed }
            return .ignored
        case .swipeMoved:
            if case .undecided = swipe, scroll.deltaX != 0 || scroll.deltaY != 0 {
                swipe = abs(scroll.deltaX) > abs(scroll.deltaY) ? .paging(travelled: 0, stepped: false) : .scrolling
            }
            guard case .paging(let travelled, let stepped) = swipe else { return .ignored }
            let distance = travelled + scroll.deltaX
            guard !stepped, abs(distance) >= Self.swipeDistance else {
                swipe = .paging(travelled: distance, stepped: stepped)
                return .consumed
            }
            swipe = .paging(travelled: distance, stepped: true)
            return .step(distance < 0 ? .forward : .backward)
        }
    }
}
