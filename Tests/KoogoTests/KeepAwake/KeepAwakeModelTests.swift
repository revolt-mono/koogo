import IOKit.pwr_mgt
import Testing

@testable import Koogo

@MainActor
struct KeepAwakeModelTests {
  @Test
  func `toggling owns exactly one display sleep assertion`() throws {
    let model = KeepAwakeModel(defaults: try scratch.makeIsolatedDefaults())
    #expect(!model.isEnabled)
    try #expect(ownedAssertionCount() == 0)

    model.isEnabled = true
    try #expect(ownedAssertionCount() == 1)

    model.isEnabled = true
    try #expect(ownedAssertionCount() == 1)

    model.isEnabled = false
    try #expect(ownedAssertionCount() == 0)
  }

  @Test
  func `enabled state survives relaunch`() throws {
    let defaults = try scratch.makeIsolatedDefaults()
    KeepAwakeModel(defaults: defaults).isEnabled = true
    try #expect(ownedAssertionCount() == 0, "a released model releases its assertion")

    let relaunched = KeepAwakeModel(defaults: defaults)
    try #expect(ownedAssertionCount() == 0, "construction has no launch effects")
    relaunched.start()
    #expect(relaunched.isEnabled)
    try #expect(ownedAssertionCount() == 1)
  }

  private let scratch = Scratch()

  private func ownedAssertionCount() throws -> Int {
    var byProcess: Unmanaged<CFDictionary>?
    #expect(IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess)
    let assertions = try #require(byProcess?.takeRetainedValue() as? [Int: [[String: Any]]])
    return (assertions[Int(getpid())] ?? []).count {
      $0[kIOPMAssertionTypeKey as String] as? String == kIOPMAssertionTypePreventUserIdleDisplaySleep as String
    }
  }
}
