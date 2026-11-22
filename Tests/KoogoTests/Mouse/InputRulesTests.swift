import Synchronization
import Testing

@testable import Koogo

struct InputRulesTests {
  @Test
  func `only one axis deltas parse as notches`() {
    #expect(WheelNotch(verticalDelta: 42, horizontalDelta: 0) == WheelNotch(axis: .vertical, direction: .positive))
    #expect(WheelNotch(verticalDelta: 0, horizontalDelta: -9) == WheelNotch(axis: .horizontal, direction: .negative))
    #expect(WheelNotch(verticalDelta: 1, horizontalDelta: 1) == nil)
    #expect(WheelNotch(verticalDelta: 0, horizontalDelta: 0) == nil)
  }

  @Test
  func `line by line applies only while a listed app is frontmost and outranks precision`() {
    var settings = MouseSettings(lineByLineApps: ["com.mitchellh.ghostty"])
    settings.isOptionPrecisionEnabled = true

    #expect(InputRules(settings, frontmostApp: "com.mitchellh.ghostty").notchMode == .lineByLine)
    #expect(InputRules(settings, frontmostApp: "com.apple.Safari").notchMode == .optionPrecision)
    #expect(InputRules(settings, frontmostApp: nil).notchMode == .optionPrecision)
    #expect(InputRules(MouseSettings(), frontmostApp: "com.mitchellh.ghostty").notchMode == .standard)
  }

  @Test
  func `notches scroll the wheel step signed by direction`() {
    let upward = WheelNotch(axis: .vertical, direction: .positive)
    let left = WheelNotch(axis: .horizontal, direction: .negative)

    #expect(rules(.slow, .natural).step(for: upward, isOptionHeld: false) == step(.vertical, 2))
    #expect(rules(.default, .natural).step(for: left, isOptionHeld: false) == step(.horizontal, -3))
    #expect(rules(.slow, .standard).step(for: upward, isOptionHeld: false) == step(.vertical, -2))
  }

  @Test
  func `option swaps between one line and the wheel step and hides option only when it did`() {
    let down = WheelNotch(axis: .vertical, direction: .negative)

    #expect(rules(.default, .natural, .standard).step(for: down, isOptionHeld: true) == step(.vertical, -3))
    #expect(rules(.default, .natural, .optionPrecision).step(for: down, isOptionHeld: false) == step(.vertical, -3))
    #expect(
      rules(.default, .natural, .optionPrecision).step(for: down, isOptionHeld: true)
        == step(.vertical, -1, stripsOption: true)
    )
    #expect(rules(.default, .natural, .lineByLine).step(for: down, isOptionHeld: false) == step(.vertical, -1))
    #expect(
      rules(.default, .natural, .lineByLine).step(for: down, isOptionHeld: true)
        == step(.vertical, -3, stripsOption: true)
    )
  }

  @Test
  func `every rule set crosses the atomic intact`() {
    let atomic = Atomic(InputRules(MouseSettings(), frontmostApp: nil))
    for wheelStep in WheelStep.allCases {
      for direction in ScrollDirection.allCases {
        for notchMode in InputRules.NotchMode.allCases {
          for isLookUpEnabled in [false, true] {
            let rules = InputRules(
              wheelStep: wheelStep,
              direction: direction,
              notchMode: notchMode,
              isLookUpEnabled: isLookUpEnabled,
            )
            atomic.store(rules, ordering: .relaxed)
            #expect(atomic.load(ordering: .relaxed) == rules)
          }
        }
      }
    }
  }

  private func rules(
    _ wheelStep: WheelStep,
    _ direction: ScrollDirection,
    _ notchMode: InputRules.NotchMode = .standard,
  ) -> InputRules {
    InputRules(wheelStep: wheelStep, direction: direction, notchMode: notchMode, isLookUpEnabled: true)
  }

  private func step(_ axis: WheelNotch.Axis, _ lines: Int32, stripsOption: Bool = false) -> ScrollStep {
    ScrollStep(axis: axis, lines: lines, stripsOption: stripsOption)
  }
}
