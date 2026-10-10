import XCTest

@testable import Koogo

final class PageStepRecognizerTests: XCTestCase {
    @MainActor
    func testWheelClicksStepAtOnceWhenSidewaysOrShiftedAndPlainVerticalOnesPassThrough() {
        let recognizer = PageStepRecognizer()
        XCTAssertEqual(recognizer.receive(wheel(shifted: true, deltaY: 3)), .step(.forward))
        XCTAssertEqual(recognizer.receive(wheel(shifted: true, deltaY: -3)), .step(.backward))
        XCTAssertEqual(recognizer.receive(wheel(shifted: true, deltaX: -3)), .step(.forward))
        XCTAssertEqual(recognizer.receive(wheel(shifted: false, deltaX: 3)), .step(.backward))
        XCTAssertEqual(recognizer.receive(wheel(shifted: true)), .ignored)
        XCTAssertEqual(recognizer.receive(wheel(shifted: false, deltaY: 3)), .ignored)
        XCTAssertEqual(recognizer.receive(wheel(shifted: false, deltaX: 3, deltaY: 3)), .ignored)
    }

    @MainActor
    func testASidewaysSwipeStepsOnceAfterEnoughTravelAndOwnsItsWholeRun() {
        let recognizer = PageStepRecognizer()
        XCTAssertEqual(recognizer.receive(swipe(.swipeBegan)), .ignored)
        XCTAssertEqual(recognizer.receive(swipe(.swipeMoved, deltaX: -15, deltaY: 2)), .consumed)
        XCTAssertEqual(recognizer.receive(swipe(.swipeMoved, deltaX: -15, deltaY: 2)), .consumed)
        XCTAssertEqual(recognizer.receive(swipe(.swipeMoved, deltaX: -15, deltaY: 2)), .step(.forward))
        XCTAssertEqual(recognizer.receive(swipe(.swipeMoved, deltaX: -30)), .consumed)
        XCTAssertEqual(recognizer.receive(swipe(.swipeMoved, deltaY: -30)), .consumed)
        XCTAssertEqual(recognizer.receive(swipe(.swipeEnded)), .consumed)

        XCTAssertEqual(recognizer.receive(swipe(.swipeBegan)), .ignored)
        XCTAssertEqual(recognizer.receive(swipe(.swipeMoved, deltaX: 45)), .step(.backward))
        XCTAssertEqual(recognizer.receive(swipe(.swipeEnded)), .consumed)
    }

    @MainActor
    func testAVerticalSwipeIsLeftToThePageEvenWhenItDriftsSideways() {
        let recognizer = PageStepRecognizer()
        XCTAssertEqual(recognizer.receive(swipe(.swipeBegan)), .ignored)
        XCTAssertEqual(recognizer.receive(swipe(.swipeMoved, deltaX: 1, deltaY: -10)), .ignored)
        XCTAssertEqual(recognizer.receive(swipe(.swipeMoved, deltaX: -60)), .ignored)
        XCTAssertEqual(recognizer.receive(swipe(.swipeEnded)), .ignored)
    }
}

private func wheel(shifted: Bool, deltaX: CGFloat = 0, deltaY: CGFloat = 0) -> PageScroll {
    PageScroll(source: .wheel(shifted: shifted), deltaX: deltaX, deltaY: deltaY)
}

private func swipe(_ source: PageScroll.Source, deltaX: CGFloat = 0, deltaY: CGFloat = 0) -> PageScroll {
    PageScroll(source: source, deltaX: deltaX, deltaY: deltaY)
}
