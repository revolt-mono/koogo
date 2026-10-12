import Synchronization
import XCTest

@testable import Koogo

final class InputRulesTests: XCTestCase {
    func testOnlyOneAxisDeltasParseAsNotches() {
        XCTAssertEqual(
            WheelNotch(verticalDelta: 42, horizontalDelta: 0),
            WheelNotch(axis: .vertical, direction: .positive)
        )
        XCTAssertEqual(
            WheelNotch(verticalDelta: 0, horizontalDelta: -9),
            WheelNotch(axis: .horizontal, direction: .negative)
        )
        XCTAssertNil(WheelNotch(verticalDelta: 1, horizontalDelta: 1))
        XCTAssertNil(WheelNotch(verticalDelta: 0, horizontalDelta: 0))
    }

    func testLineByLineAppliesOnlyWhileAListedAppIsFrontmostAndOutranksPrecision() {
        var settings = MouseSettings(lineByLineApps: ["com.mitchellh.ghostty"])
        settings.isOptionPrecisionEnabled = true

        XCTAssertEqual(InputRules(settings, frontmostApp: "com.mitchellh.ghostty").notchMode, .lineByLine)
        XCTAssertEqual(InputRules(settings, frontmostApp: "com.apple.Safari").notchMode, .optionPrecision)
        XCTAssertEqual(InputRules(settings, frontmostApp: nil).notchMode, .optionPrecision)
        XCTAssertEqual(InputRules(MouseSettings(), frontmostApp: "com.mitchellh.ghostty").notchMode, .standard)
    }

    func testNotchesScrollTheWheelStepSignedByDirection() {
        let upward = WheelNotch(axis: .vertical, direction: .positive)
        let left = WheelNotch(axis: .horizontal, direction: .negative)

        XCTAssertEqual(rules(.slow, .natural).step(for: upward, isOptionHeld: false), step(.vertical, 2))
        XCTAssertEqual(rules(.default, .natural).step(for: left, isOptionHeld: false), step(.horizontal, -3))
        XCTAssertEqual(rules(.slow, .standard).step(for: upward, isOptionHeld: false), step(.vertical, -2))
    }

    func testOptionSwapsBetweenOneLineAndTheWheelStepAndHidesOptionOnlyWhenItDid() {
        let down = WheelNotch(axis: .vertical, direction: .negative)

        XCTAssertEqual(
            rules(.default, .natural, .standard).step(for: down, isOptionHeld: true),
            step(.vertical, -3)
        )
        XCTAssertEqual(
            rules(.default, .natural, .optionPrecision).step(for: down, isOptionHeld: false),
            step(.vertical, -3)
        )
        XCTAssertEqual(
            rules(.default, .natural, .optionPrecision).step(for: down, isOptionHeld: true),
            step(.vertical, -1, stripsOption: true)
        )
        XCTAssertEqual(
            rules(.default, .natural, .lineByLine).step(for: down, isOptionHeld: false),
            step(.vertical, -1)
        )
        XCTAssertEqual(
            rules(.default, .natural, .lineByLine).step(for: down, isOptionHeld: true),
            step(.vertical, -3, stripsOption: true)
        )
    }

    func testEveryRuleSetCrossesTheAtomicIntact() {
        let atomic = Atomic(InputRules(MouseSettings(), frontmostApp: nil))
        for wheelStep in WheelStep.allCases {
            for direction in ScrollDirection.allCases {
                for notchMode in InputRules.NotchMode.allCases {
                    for isLookUpEnabled in [false, true] {
                        let rules = InputRules(
                            wheelStep: wheelStep,
                            direction: direction,
                            notchMode: notchMode,
                            isLookUpEnabled: isLookUpEnabled
                        )
                        atomic.store(rules, ordering: .relaxed)
                        XCTAssertEqual(atomic.load(ordering: .relaxed), rules)
                    }
                }
            }
        }
    }

    private func rules(
        _ wheelStep: WheelStep,
        _ direction: ScrollDirection,
        _ notchMode: InputRules.NotchMode = .standard
    ) -> InputRules {
        InputRules(wheelStep: wheelStep, direction: direction, notchMode: notchMode, isLookUpEnabled: true)
    }

    private func step(_ axis: WheelNotch.Axis, _ lines: Int32, stripsOption: Bool = false) -> ScrollStep {
        ScrollStep(axis: axis, lines: lines, stripsOption: stripsOption)
    }
}
