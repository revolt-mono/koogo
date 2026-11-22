import Testing

@testable import Koogo

struct ActivityFormattingTests {
  @Test
  func `bytes switch units at a gigabyte`() {
    #expect(Measure(bytes: 22_752_738_181).text == "21.19 GB")
    #expect(Measure(bytes: 1 << 30).text == "1.00 GB")
    #expect(Measure(bytes: 956_301_312).text == "912 MB")
    #expect(Measure(bytes: 0).text == "0 MB")
  }

  @Test
  func `percent rounds to whole numbers`() {
    #expect(Measure(fraction: 0.314).text == "31%")
    #expect(Measure(fraction: 0.005).value == "1")
    #expect(Measure(fraction: 1).text == "100%")
  }

  @Test
  func `watts keep one decimal`() {
    #expect(Measure(watts: 14.26).text == "14.3 W")
    #expect(Measure(watts: 0).value == "0.0")
  }
}
