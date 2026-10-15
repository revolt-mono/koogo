import Foundation
import IOKit.pwr_mgt
import Observation
import os

/// A display sleep assertion also blocks idle system sleep, so one assertion covers both.
@MainActor
@Observable
final class KeepAwakeModel {
    private static let key = "keep-awake"

    private let defaults: UserDefaults
    @ObservationIgnored private var assertion: IOPMAssertionID?

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.key)
            applyAssertion()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.key)
        applyAssertion()
    }

    deinit {
        if let assertion {
            IOPMAssertionRelease(assertion)
        }
    }

    private func applyAssertion() {
        switch (isEnabled, assertion) {
        case (true, nil):
            var id = IOPMAssertionID(0)
            let status = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Koogo keeps the Mac awake" as CFString,
                &id
            )
            guard status == kIOReturnSuccess else {
                Logger.app.warning("could not create keep awake assertion: \(status, privacy: .public)")
                isEnabled = false
                return
            }
            assertion = id
        case (false, let id?):
            IOPMAssertionRelease(id)
            assertion = nil
        case (true, _?), (false, nil):
            break
        }
    }
}
