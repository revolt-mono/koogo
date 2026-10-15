import Foundation
import IOKit.pwr_mgt
import XCTest

@testable import Koogo

@MainActor
final class KeepAwakeModelTests: XCTestCase {
    func testTogglingOwnsExactlyOneDisplaySleepAssertion() throws {
        let model = KeepAwakeModel(defaults: try makeIsolatedDefaults())
        XCTAssertFalse(model.isEnabled)
        XCTAssertEqual(try ownedAssertionCount(), 0)

        model.isEnabled = true
        XCTAssertEqual(try ownedAssertionCount(), 1)

        model.isEnabled = true
        XCTAssertEqual(try ownedAssertionCount(), 1)

        model.isEnabled = false
        XCTAssertEqual(try ownedAssertionCount(), 0)
    }

    func testEnabledStateSurvivesRelaunch() throws {
        let defaults = try makeIsolatedDefaults()
        KeepAwakeModel(defaults: defaults).isEnabled = true

        let relaunched = KeepAwakeModel(defaults: defaults)
        XCTAssertTrue(relaunched.isEnabled)
        XCTAssertEqual(try ownedAssertionCount(), 1)
    }

    private func ownedAssertionCount() throws -> Int {
        var byProcess: Unmanaged<CFDictionary>?
        XCTAssertEqual(IOPMCopyAssertionsByProcess(&byProcess), kIOReturnSuccess)
        let assertions = try XCTUnwrap(byProcess?.takeRetainedValue() as? [Int: [[String: Any]]])
        return (assertions[Int(getpid())] ?? []).count {
            $0[kIOPMAssertionTypeKey as String] as? String == kIOPMAssertionTypePreventUserIdleDisplaySleep as String
        }
    }
}
