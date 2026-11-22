import Testing

@testable import Koogo

struct DisplayLocaleTests {
  @Test
  func `units show two whole units at most`() {
    #expect(Duration.seconds(80 * 60).formatted(.displayUnits(allowed: [.hours, .minutes])) == "1h 20m")
    #expect(Duration.seconds(45 * 60 + 30).formatted(.displayUnits(allowed: [.hours, .minutes])) == "45m")
    #expect(
      Duration.seconds(26 * 60 * 60 + 5 * 60).formatted(.displayUnits(allowed: [.days, .hours, .minutes])) == "1d 2h"
    )
  }
}
