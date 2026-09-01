import XCTest

@testable import Koogo

final class TodoPrioritySpringTests: XCTestCase {
    func testRetargetingPreservesMotion() {
        var spring = TodoPrioritySpring(isSelected: false)
        spring.retarget(isSelected: true)
        for _ in 0..<5 {
            XCTAssertTrue(spring.advance(by: 1.0 / 60))
        }

        let progress = spring.progress
        let velocity = spring.velocity
        spring.retarget(isSelected: false)

        XCTAssertEqual(spring.progress, progress)
        XCTAssertEqual(spring.velocity, velocity)
        XCTAssertEqual(spring.target, 0)

        var isActive = true
        for _ in 0..<600 where isActive {
            isActive = spring.advance(by: 1.0 / 60)
        }
        XCTAssertFalse(isActive)
        XCTAssertEqual(spring.progress, 0)
        XCTAssertEqual(spring.velocity, 0)
    }
}
