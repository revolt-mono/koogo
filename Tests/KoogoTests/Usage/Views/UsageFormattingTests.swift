import Foundation
import XCTest

@testable import Koogo

final class UsageFormattingTests: XCTestCase {
    func testCostsRoundToCents() throws {
        XCTAssertEqual(UsageFormatting.cost(0.005), "$0.01")
        XCTAssertEqual(UsageFormatting.cost(0.01), "$0.01")
        XCTAssertEqual(
            UsageFormatting.cost(try XCTUnwrap(Decimal(string: "0.025"))),
            "$0.03"
        )
    }

    func testTokensUseCompactNotation() {
        XCTAssertEqual(UsageFormatting.tokens(999), "999")
        XCTAssertEqual(UsageFormatting.tokens(1_500), "1.5K")
    }

    func testPercentagesRoundToOneDecimalPlace() throws {
        XCTAssertEqual(UsageFormatting.percentage(1), "100%")
        XCTAssertEqual(UsageFormatting.percentage(0), "0%")
        XCTAssertEqual(
            UsageFormatting.percentage(
                try XCTUnwrap(Decimal(string: "0.125"))
            ),
            "12.5%"
        )
    }
}
