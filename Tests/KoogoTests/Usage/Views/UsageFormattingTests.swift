import Foundation
import XCTest

@testable import Koogo

final class UsageFormattingTests: XCTestCase {
    func testCostsRoundToCents() throws {
        XCTAssertEqual((0.005 as Decimal).formatted(.usd), "$0.01")
        XCTAssertEqual((0.01 as Decimal).formatted(.usd), "$0.01")
        XCTAssertEqual(try XCTUnwrap(Decimal(string: "0.025")).formatted(.usd), "$0.03")
    }

    func testTokensUseCompactNotation() {
        XCTAssertEqual((999 as UInt64).formatted(.compactTokens), "999")
        XCTAssertEqual((1_500 as UInt64).formatted(.compactTokens), "1.5K")
    }

    func testPercentagesRoundToOneDecimalPlace() throws {
        XCTAssertEqual((1 as Decimal).formatted(.usagePercent), "100%")
        XCTAssertEqual((0 as Decimal).formatted(.usagePercent), "0%")
        XCTAssertEqual(try XCTUnwrap(Decimal(string: "0.125")).formatted(.usagePercent), "12.5%")
    }
}
