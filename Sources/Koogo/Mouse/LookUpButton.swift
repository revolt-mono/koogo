import ApplicationServices
import Carbon.HIToolbox
import os

struct LookUpButton {
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

  func remap(_ event: CGEvent) -> EventDisposition {
    guard event.getIntegerValueField(.mouseEventButtonNumber) == Self.buttonNumber else {
      return .deliver
    }
    if event.type == .otherMouseDown {
      post(timestamp: event.timestamp)
    }
    return .drop
  }

  /// core graphics numbers mouse button 4 as 3.
  private static let buttonNumber: Int64 = 3
  private static let keyCode = CGKeyCode(kVK_ANSI_D)

  private let keyDown: CGEvent
  private let keyUp: CGEvent

  private func post(timestamp: CGEventTimestamp) {
    keyDown.timestamp = timestamp
    keyUp.timestamp = timestamp
    keyDown.post(tap: .cgSessionEventTap)
    keyUp.post(tap: .cgSessionEventTap)
  }
}
