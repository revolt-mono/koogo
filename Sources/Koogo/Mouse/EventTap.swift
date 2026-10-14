@preconcurrency import ApplicationServices
import Foundation
import Observation
import Synchronization
import os

/// Owns the session event tap. The main actor publishes rules as one atomic word, which the callback on the tap's thread reads without locks, lookups, or allocation.
@MainActor
@Observable
final class EventTap {
    private(set) var isRunning = false

    @ObservationIgnored private var port: CFMachPort?
    private let rules = Atomic(InputRules(MouseSettings(), frontmostApp: nil))
    private nonisolated(unsafe) let rewriter = ScrollRewriter()
    private let lookUp = LookUpShortcut()

    /// Installs on the first run and again after the tap stops; installing needs Accessibility trust.
    func run(_ rules: InputRules) {
        self.rules.store(rules, ordering: .relaxed)
        if port == nil {
            port = install()
        }
        if let port {
            CGEvent.tapEnable(tap: port, enable: true)
        }
        isRunning = port != nil
    }

    func pause() {
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        isRunning = false
    }

    /// Declared outside any main actor method, whose isolation a closure would inherit and then trap on the tap's thread.
    nonisolated static let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }
        return Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue().handle(type, event, proxy: proxy)
    }

    private func install() -> CFMachPort? {
        let mask =
            CGEventMask(1 << CGEventType.scrollWheel.rawValue)
            | CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
        guard
            let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: Self.callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            Logger.mouse.error("couldn't install the event tap")
            return nil
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        let thread = Thread { [self, source] in
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CFRunLoopRun()
            Task { @MainActor in
                stopped()
            }
        }
        thread.name = "Koogo Event Tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        return port
    }

    private func stopped() {
        Logger.mouse.warning("event tap stopped")
        port = nil
        isRunning = false
    }

    private func resume() {
        guard isRunning, let port else {
            return
        }
        Logger.mouse.notice("event tap re-enabled after macOS disabled it")
        CGEvent.tapEnable(tap: port, enable: true)
    }

    private nonisolated func handle(
        _ type: CGEventType,
        _ event: CGEvent,
        proxy: CGEventTapProxy
    ) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .scrollWheel:
            switch rewriter.rewrite(event, rules: rules.load(ordering: .relaxed)) {
            case .deliver:
                return pass
            case .drop:
                return nil
            case .post(let stripped):
                stripped.post(via: proxy)
                return nil
            }
        case .otherMouseDown, .otherMouseUp:
            guard let lookUp, rules.load(ordering: .relaxed).isLookUpEnabled,
                event.getIntegerValueField(.mouseEventButtonNumber) == LookUpShortcut.buttonNumber
            else {
                return pass
            }
            if type == .otherMouseDown {
                lookUp.post(timestamp: event.timestamp)
            }
            return nil
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            Task { @MainActor in
                resume()
            }
            return pass
        default:
            return pass
        }
    }
}

/// Mouse button 4 becomes Control-Command-D, the system Look Up shortcut.
private struct LookUpShortcut {
    static let buttonNumber: Int64 = 3
    private static let keyCode = CGKeyCode(0x02)

    private let keyDown: CGEvent
    private let keyUp: CGEvent

    init?() {
        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: Self.keyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: Self.keyCode, keyDown: false)
        else {
            Logger.mouse.error("couldn't build the look up key events; button 4 passes through")
            return nil
        }
        keyDown.flags = [.maskCommand, .maskControl]
        keyUp.flags = [.maskCommand, .maskControl]
        self.keyDown = keyDown
        self.keyUp = keyUp
    }

    func post(timestamp: CGEventTimestamp) {
        keyDown.timestamp = timestamp
        keyUp.timestamp = timestamp
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }
}

/// Packs the rules into one word so the tap thread loads a coherent snapshot.
extension InputRules: AtomicRepresentable {
    typealias AtomicRepresentation = UInt32.AtomicRepresentation

    static func encodeAtomicRepresentation(_ value: consuming InputRules) -> AtomicRepresentation {
        let bits =
            value.wheelStep.rawValue
            | value.direction.rawValue << 4
            | value.notchMode.rawValue << 8
            | (value.isLookUpEnabled ? 1 : 0) << 12
        return UInt32.encodeAtomicRepresentation(bits)
    }

    static func decodeAtomicRepresentation(_ storage: consuming AtomicRepresentation) -> InputRules {
        let bits = UInt32.decodeAtomicRepresentation(storage)
        guard let wheelStep = WheelStep(rawValue: bits & 0xF),
            let direction = ScrollDirection(rawValue: bits >> 4 & 0xF),
            let notchMode = NotchMode(rawValue: bits >> 8 & 0xF)
        else {
            preconditionFailure("only encodeAtomicRepresentation writes the word")
        }
        return InputRules(
            wheelStep: wheelStep,
            direction: direction,
            notchMode: notchMode,
            isLookUpEnabled: bits >> 12 & 1 == 1
        )
    }
}
