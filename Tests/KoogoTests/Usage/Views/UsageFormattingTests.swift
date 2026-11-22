import Foundation
import Testing

@testable import Koogo

struct UsageFormattingTests {
  @Test
  func `costs round to cents`() {
    #expect((0.005 as Decimal).formatted(.usd) == "$0.01")
    #expect((0.01 as Decimal).formatted(.usd) == "$0.01")
    #expect(Decimal(string: "0.025")?.formatted(.usd) == "$0.03")
  }

  @Test
  func `tokens use compact notation`() {
    #expect((999 as UInt64).formatted(.compactTokens) == "999")
    #expect((1_500 as UInt64).formatted(.compactTokens) == "1.5K")
  }

  @Test
  func `percentages round to one decimal place`() {
    #expect((1 as Decimal).formatted(.usagePercent) == "100%")
    #expect((0 as Decimal).formatted(.usagePercent) == "0%")
    #expect(Decimal(string: "0.1225")?.formatted(.usagePercent) == "12.3%")
  }
}
