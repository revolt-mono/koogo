import Foundation
import XCTest

@testable import Koogo

final class BreakReminderCountdownTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testStatusFollowsTheDeadline() {
        let countdown = BreakReminderCountdown.scheduled(interval: .oneHour, deadline: now.addingTimeInterval(600))

        XCTAssertEqual(countdown.status(at: now), .running(remaining: 600))
        XCTAssertEqual(countdown.status(at: now.addingTimeInterval(600)), .expired)
        XCTAssertEqual(
            BreakReminderCountdown.paused(interval: .twoHours, remaining: 42).status(at: now),
            .paused(remaining: 42)
        )
    }

    func testToggleSwapsRunningAndPausedKeepingTheRemainingTime() {
        let running = BreakReminderCountdown.scheduled(interval: .oneHour, deadline: now.addingTimeInterval(2_700))
        XCTAssertEqual(running.change(for: .toggle, at: now), .pause(.oneHour, remaining: 2_700))

        let paused = BreakReminderCountdown.paused(interval: .oneHour, remaining: 2_700)
        XCTAssertEqual(paused.change(for: .toggle, at: now), .run(.oneHour, for: 2_700))
    }

    func testRestartAndExpiredToggleRunTheFullInterval() {
        let expired = BreakReminderCountdown.scheduled(interval: .ninetyMinutes, deadline: now)
        XCTAssertEqual(expired.change(for: .toggle, at: now), .run(.ninetyMinutes, for: 5_400))

        let running = BreakReminderCountdown.scheduled(interval: .ninetyMinutes, deadline: now.addingTimeInterval(9))
        XCTAssertEqual(running.change(for: .restart, at: now), .run(.ninetyMinutes, for: 5_400))

        let paused = BreakReminderCountdown.paused(interval: .ninetyMinutes, remaining: 9)
        XCTAssertEqual(paused.change(for: .restart, at: now), .run(.ninetyMinutes, for: 5_400))
    }

    func testChangingIntervalResetsToTheNewDurationInTheCurrentMode() {
        let running = BreakReminderCountdown.scheduled(interval: .oneHour, deadline: now.addingTimeInterval(9))
        XCTAssertEqual(running.change(for: .setInterval(.twoHours), at: now), .run(.twoHours, for: 7_200))
        XCTAssertNil(running.change(for: .setInterval(.oneHour), at: now))

        let paused = BreakReminderCountdown.paused(interval: .oneHour, remaining: 9)
        XCTAssertEqual(
            paused.change(for: .setInterval(.ninetyMinutes), at: now),
            .pause(.ninetyMinutes, remaining: 5_400)
        )

        let expired = BreakReminderCountdown.scheduled(interval: .oneHour, deadline: now)
        XCTAssertEqual(expired.change(for: .setInterval(.twoHours), at: now), .pause(.twoHours, remaining: 7_200))
    }

    func testValidityBoundsPausedRemainingByTheInterval() {
        XCTAssertTrue(BreakReminderCountdown.paused(interval: .oneHour, remaining: 3_600).isValid)
        XCTAssertFalse(BreakReminderCountdown.paused(interval: .oneHour, remaining: 3_601).isValid)
        XCTAssertFalse(BreakReminderCountdown.paused(interval: .oneHour, remaining: 0).isValid)
        XCTAssertTrue(BreakReminderCountdown.scheduled(interval: .oneHour, deadline: .distantPast).isValid)
        XCTAssertFalse(
            BreakReminderCountdown.scheduled(interval: .oneHour, deadline: Date(timeIntervalSinceReferenceDate: .nan))
                .isValid
        )
    }

    func testTimeTextUsesHoursOnlyWhenNeeded() {
        XCTAssertEqual(BreakReminderStatus.paused(remaining: 7_200).timeText, "2:00:00")
        XCTAssertEqual(BreakReminderStatus.running(remaining: 3_599.1).timeText, "1:00:00")
        XCTAssertEqual(BreakReminderStatus.running(remaining: 3_599).timeText, "59:59")
        XCTAssertEqual(BreakReminderStatus.expired.timeText, "00:00")
    }
}
