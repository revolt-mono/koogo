import ApplicationServices
import Foundation
import Observation
import os
import Synchronization

enum EventDisposition {
  case deliver
  case drop
}

/// the tap thread must handle events without locks, lookups, or allocation.
@MainActor
@Observable
final class EventTap {
  nonisolated static let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
    guard let userInfo else {
      return Unmanaged.passUnretained(event)
    }
    let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
    return switch tap.handle(type, event, proxy: proxy) {
    case .deliver: Unmanaged.passUnretained(event)
    case .drop: nil
    }
  }

  var isStopped: Bool {
    state == .stopped
  }

  /// installing the tap requires accessibility trust.
  func run(_ rules: InputRules) {
    self.rules.store(rules, ordering: .relaxed)
    let port: CFMachPort? =
      switch state {
      case .idle,
           .stopped: install()
      case .paused(let port),
           .running(let port): port
      }
    guard let port else {
      state = .stopped
      return
    }
    CGEvent.tapEnable(tap: port, enable: true)
    state = .running(port)
  }

  func pause() {
    switch state {
    case .running(let port):
      CGEvent.tapEnable(tap: port, enable: false)
      state = .paused(port)

    case .stopped:
      state = .idle

    case .idle,
         .paused:
      break
    }
  }

  private enum State: Equatable {
    case idle
    case paused(CFMachPort)
    case running(CFMachPort)
    /// running was requested, but the tap couldn't install or its run loop exited.
    case stopped
  }

  private var state = State.idle

  private let rules = Atomic(InputRules(MouseSettings(), frontmostApp: nil))
  private nonisolated(unsafe) let rewriter = ScrollRewriter()
  private nonisolated(unsafe) let lookUp = LookUpButton()

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
        userInfo: Unmanaged.passUnretained(self).toOpaque(),
      )
    else {
      Logger.mouse.error("couldn't install the event tap")
      return nil
    }

    nonisolated(unsafe) let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
    let thread = Thread { [self] in
      CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
      CFRunLoopRun()
      Task { @MainActor in
        runLoopDidExit()
      }
    }
    thread.name = "Koogo Event Tap"
    thread.qualityOfService = .userInteractive
    thread.start()
    return port
  }

  private func runLoopDidExit() {
    Logger.mouse.warning("event tap stopped")
    state =
      if case .running = state {
        .stopped
      } else {
        .idle
      }
  }

  private func systemDidDisableTap() {
    guard case .running(let port) = state else {
      return
    }
    Logger.mouse.notice("event tap re-enabled after macOS disabled it")
    CGEvent.tapEnable(tap: port, enable: true)
  }

  private nonisolated func handle(
    _ type: CGEventType,
    _ event: CGEvent,
    proxy: CGEventTapProxy,
  ) -> EventDisposition {
    let rules = rules.load(ordering: .relaxed)
    switch type {
    case .scrollWheel:
      return rewriter.rewrite(event, rules: rules) { $0.post(via: proxy) }

    case .otherMouseDown,
         .otherMouseUp:
      guard rules.isLookUpEnabled, let lookUp else {
        return .deliver
      }
      return lookUp.remap(event)

    case .tapDisabledByTimeout,
         .tapDisabledByUserInput:
      Task { @MainActor in
        systemDidDisableTap()
      }
      return .deliver

    default:
      return .deliver
    }
  }
}
