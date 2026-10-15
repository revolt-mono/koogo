@preconcurrency import ApplicationServices
import os

enum ScrollRewrite: Equatable {
    case deliver
    case drop
}

/// posting adapters borrow the reusable event only for the synchronous call.
struct PostedScrollEvent: ~Copyable {
    private let event: CGEvent

    fileprivate init(_ event: CGEvent) {
        self.event = event
    }

    var type: CGEventType { event.type }
    var flags: CGEventFlags { event.flags }
    var timestamp: CGEventTimestamp { event.timestamp }
    var location: CGPoint { event.location }

    func integerValue(for field: CGEventField) -> Int64 {
        event.getIntegerValueField(field)
    }

    func post(via proxy: CGEventTapProxy) {
        event.tapPostEvent(proxy)
    }
}

/// single-threaded wheel-notch rewriting with reusable posted events and no per-call allocation.
final class ScrollRewriter {
    private static let pixelsPerLine: Int64 = 16

    private let optionStrip: OptionStrip?

    init() {
        let source = CGEventSource(stateID: .hidSystemState)
        source?.pixelsPerLine = Double(Self.pixelsPerLine)
        optionStrip = OptionStrip(source: source)
    }

    /// posts replacements synchronously before returning drop.
    func rewrite(_ event: CGEvent, rules: InputRules, post: (borrowing PostedScrollEvent) -> Void) -> ScrollRewrite {
        guard Self.isWheelNotchEvent(event) else {
            return .deliver
        }
        guard
            let notch = WheelNotch(
                verticalDelta: event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
                horizontalDelta: event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            )
        else {
            return .drop
        }

        let step = rules.step(for: notch, isOptionHeld: event.flags.contains(.maskAlternate))
        guard step.stripsOption else {
            Self.write(step, to: event)
            return .deliver
        }
        guard let optionStrip else {
            return .drop
        }
        optionStrip.post(step, from: event, using: post)
        return .drop
    }

    /// trackpads and magic mouse scrolling carry continuous or phased events; wheel notches carry neither.
    private static func isWheelNotchEvent(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0
            && event.getIntegerValueField(.scrollWheelEventScrollPhase) == 0
            && event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0
            && event.getIntegerValueField(.mouseEventSubtype) == Int64(CGEventMouseSubtype.defaultType.rawValue)
            && event.getIntegerValueField(.tabletEventDeviceID) == 0
    }

    fileprivate static func write(_ step: ScrollStep, to event: CGEvent) {
        let linesY: Int64 = step.axis == .vertical ? Int64(step.lines) : 0
        let linesX: Int64 = step.axis == .horizontal ? Int64(step.lines) : 0
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: linesY)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: linesX)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis3, value: 0)
        event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1, value: linesY * 65_536)
        event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2, value: linesX * 65_536)
        event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis3, value: 0)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: linesY * pixelsPerLine)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: linesX * pixelsPerLine)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis3, value: 0)
        event.setIntegerValueField(.scrollWheelEventScrollCount, value: 1)
    }
}

private struct OptionStrip {
    private static let leftOptionFlag = CGEventFlags(rawValue: 0x20)
    private static let rightOptionFlag = CGEventFlags(rawValue: 0x40)
    private static let allOptionFlags: CGEventFlags = [.maskAlternate, leftOptionFlag, rightOptionFlag]
    private static let leftOptionKey = CGKeyCode(0x3A)
    private static let rightOptionKey = CGKeyCode(0x3D)

    private let vertical: CGEvent
    private let horizontal: CGEvent
    private let optionReleased: CGEvent
    private let optionRestored: CGEvent

    init?(source: CGEventSource?) {
        guard
            let vertical = CGEvent(
                scrollWheelEvent2Source: source,
                units: .line,
                wheelCount: 1,
                wheel1: 0,
                wheel2: 0,
                wheel3: 0
            ),
            let horizontal = CGEvent(
                scrollWheelEvent2Source: source,
                units: .line,
                wheelCount: 2,
                wheel1: 0,
                wheel2: 0,
                wheel3: 0
            ),
            let optionReleased = CGEvent(source: source),
            let optionRestored = CGEvent(source: source)
        else {
            Logger.mouse.error("couldn't build the option-stripped scroll events; option-held notches drop")
            return nil
        }
        optionReleased.type = .flagsChanged
        optionRestored.type = .flagsChanged
        self.vertical = vertical
        self.horizontal = horizontal
        self.optionReleased = optionReleased
        self.optionRestored = optionRestored
    }

    /// returning the notch from the tap would deliver the notch after both posted option changes.
    func post(_ step: ScrollStep, from event: CGEvent, using post: (borrowing PostedScrollEvent) -> Void) {
        let originalFlags = event.flags
        let strippedFlags = originalFlags.subtracting(Self.allOptionFlags)
        let optionKey = Int64(originalFlags.contains(Self.rightOptionFlag) ? Self.rightOptionKey : Self.leftOptionKey)

        let notch = step.axis == .vertical ? vertical : horizontal
        notch.location = event.location
        notch.flags = strippedFlags
        notch.timestamp = event.timestamp
        ScrollRewriter.write(step, to: notch)

        optionReleased.flags = strippedFlags
        optionReleased.timestamp = event.timestamp
        optionReleased.setIntegerValueField(.keyboardEventKeycode, value: optionKey)
        optionRestored.flags = originalFlags
        optionRestored.timestamp = event.timestamp
        optionRestored.setIntegerValueField(.keyboardEventKeycode, value: optionKey)
        post(PostedScrollEvent(optionReleased))
        post(PostedScrollEvent(notch))
        post(PostedScrollEvent(optionRestored))
    }
}
