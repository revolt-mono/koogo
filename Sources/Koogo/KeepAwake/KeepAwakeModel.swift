import Foundation
import IOKit.pwr_mgt
import Observation
import os

/// app-scoped; started by the app at launch. blocking idle display sleep also blocks idle system sleep.
@MainActor
@Observable
final class KeepAwakeModel {
  init(defaults: UserDefaults) {
    self.defaults = defaults
  }

  var isEnabled: Bool {
    get {
      access(keyPath: \.isEnabled)
      return assertion != nil
    }
    set {
      defaults.set(newValue, forKey: Self.key)
      hold(newValue)
    }
  }

  func start() {
    hold(defaults.bool(forKey: Self.key))
  }

  /// `PersistedValue` encodes property lists, which reject a top-level scalar.
  private static let key = "keep-awake"

  private let defaults: UserDefaults
  @ObservationIgnored private var assertion: DisplaySleepAssertion?

  /// notifies on every attempt, since a refused assertion leaves `assertion` unchanged while the toggle shows the request.
  private func hold(_ isHeld: Bool) {
    withMutation(keyPath: \.isEnabled) {
      if !isHeld {
        assertion = nil
      } else if assertion == nil {
        assertion = DisplaySleepAssertion()
      }
    }
  }
}

private struct DisplaySleepAssertion: ~Copyable {
  init?() {
    var id = IOPMAssertionID(0)
    let status = IOPMAssertionCreateWithName(
      kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
      IOPMAssertionLevel(kIOPMAssertionLevelOn),
      "Koogo keeps the Mac awake" as CFString,
      &id,
    )
    guard status == kIOReturnSuccess else {
      Logger.app.warning("could not create keep awake assertion: \(status, privacy: .public)")
      return nil
    }
    self.id = id
  }

  deinit {
    IOPMAssertionRelease(id)
  }

  private let id: IOPMAssertionID
}
