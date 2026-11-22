import Foundation
import Testing

@testable import Koogo

struct BreakReminderCountdownTests {
  @Test
  func `status follows the deadline`() {
    let countdown = BreakReminderCountdown.scheduled(interval: .oneHour, deadline: now.addingTimeInterval(600))

    #expect(countdown.status(at: now) == .running(remaining: 600))
    #expect(countdown.status(at: now.addingTimeInterval(600)) == .expired)
    #expect(BreakReminderCountdown.paused(interval: .twoHours, remaining: 42).status(at: now) == .paused(remaining: 42))
  }

  @Test
  func `toggle swaps running and paused keeping the remaining time`() {
    let running = BreakReminderCountdown.scheduled(interval: .oneHour, deadline: now.addingTimeInterval(2_700))
    #expect(running.change(for: .toggle, at: now) == .pause(.oneHour, remaining: 2_700))

    let paused = BreakReminderCountdown.paused(interval: .oneHour, remaining: 2_700)
    #expect(paused.change(for: .toggle, at: now) == .run(.oneHour, for: 2_700))
  }

  @Test
  func `restart and expired toggle run the full interval`() {
    let expired = BreakReminderCountdown.scheduled(interval: .ninetyMinutes, deadline: now)
    #expect(expired.change(for: .toggle, at: now) == .run(.ninetyMinutes, for: 5_400))

    let running = BreakReminderCountdown.scheduled(interval: .ninetyMinutes, deadline: now.addingTimeInterval(9))
    #expect(running.change(for: .restart, at: now) == .run(.ninetyMinutes, for: 5_400))

    let paused = BreakReminderCountdown.paused(interval: .ninetyMinutes, remaining: 9)
    #expect(paused.change(for: .restart, at: now) == .run(.ninetyMinutes, for: 5_400))
  }

  @Test
  func `changing interval resets to the new duration in the current mode`() {
    let running = BreakReminderCountdown.scheduled(interval: .oneHour, deadline: now.addingTimeInterval(9))
    #expect(running.change(for: .setInterval(.twoHours), at: now) == .run(.twoHours, for: 7_200))
    #expect(running.change(for: .setInterval(.oneHour), at: now) == nil)

    let paused = BreakReminderCountdown.paused(interval: .oneHour, remaining: 9)
    #expect(paused.change(for: .setInterval(.ninetyMinutes), at: now) == .pause(.ninetyMinutes, remaining: 5_400))

    let expired = BreakReminderCountdown.scheduled(interval: .oneHour, deadline: now)
    #expect(expired.change(for: .setInterval(.twoHours), at: now) == .pause(.twoHours, remaining: 7_200))
  }

  @Test
  func `validity bounds remaining by the interval`() {
    #expect(BreakReminderCountdown.paused(interval: .oneHour, remaining: 3_600).isValid(at: now))
    #expect(!BreakReminderCountdown.paused(interval: .oneHour, remaining: 3_601).isValid(at: now))
    #expect(!BreakReminderCountdown.paused(interval: .oneHour, remaining: 0).isValid(at: now))
    #expect(BreakReminderCountdown.scheduled(interval: .oneHour, deadline: .distantPast).isValid(at: now))
    #expect(
      BreakReminderCountdown.scheduled(interval: .oneHour, deadline: now.addingTimeInterval(3_600)).isValid(
        at: now
      )
    )
    #expect(
      !BreakReminderCountdown.scheduled(interval: .oneHour, deadline: now.addingTimeInterval(3_601)).isValid(
        at: now
      )
    )
    #expect(
      !BreakReminderCountdown.scheduled(interval: .oneHour, deadline: Date(timeIntervalSinceReferenceDate: .nan))
        .isValid(at: now)
    )
  }

  @Test
  func `time text uses hours only when needed`() {
    #expect(BreakReminderStatus.paused(remaining: 7_200).timeText == "2:00:00")
    #expect(BreakReminderStatus.running(remaining: 3_599.1).timeText == "1:00:00")
    #expect(BreakReminderStatus.running(remaining: 3_599).timeText == "59:59")
    #expect(BreakReminderStatus.expired.timeText == "00:00")
  }

  private let now = Date(timeIntervalSince1970: 1_000)
}
