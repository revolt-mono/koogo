@preconcurrency import ApplicationServices
import Carbon.HIToolbox
import Foundation
import Observation
import Synchronization
import os

/// the main actor publishes atomic rules; the tap thread handles events without locks, lookups, or allocation,
/// and only a tap that macOS disabled hops back to the main actor.
@MainActor
@Observable
final class EventTap {
    private enum State: Equatable {
        case notInstalled
        case paused(CFMachPort)
        case running(CFMachPort)
    }

    private var state = State.notInstalled

    var isRunning: Bool {
        if case .running = state { true } else { false }
    }

    private let rules = Atomic(InputRules(MouseSettings(), frontmostApp: nil))
    private nonisolated(unsafe) let rewriter = ScrollRewriter()
    private let lookUp = LookUpShortcut()

    /// installs initially and after a stopped tap; accessibility trust is required.
    func run(_ rules: InputRules) {
        self.rules.store(rules, ordering: .relaxed)
        let port: CFMachPort? =
            switch state {
            case .notInstalled: install()
            case .paused(let port), .running(let port): port
            }
        guard let port else {
            return
        }
        CGEvent.tapEnable(tap: port, enable: true)
        state = .running(port)
    }

    func pause() {
        guard case .running(let port) = state else {
            return
        }
        CGEvent.tapEnable(tap: port, enable: false)
        state = .paused(port)
    }

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
                Logger.mouse.warning("event tap stopped")
                state = .notInstalled
            }
        }
        thread.name = "Koogo Event Tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        return port
    }

    private func resume() {
        guard case .running(let port) = state else {
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
            switch rewriter.rewrite(event, rules: rules.load(ordering: .relaxed), post: { $0.post(via: proxy) }) {
            case .deliver:
                return pass
            case .drop:
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

private struct LookUpShortcut {
    /// core graphics numbers mouse button 4 as 3.
    static let buttonNumber: Int64 = 3
    private static let keyCode = CGKeyCode(kVK_ANSI_D)

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
