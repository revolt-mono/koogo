import Foundation

extension Date {
    private static let fractionalISO8601 = ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let wholeISO8601 = ISO8601FormatStyle()

    init?(iso8601 text: String) {
        guard
            let date = (try? Self.fractionalISO8601.parse(text))
                ?? (try? Self.wholeISO8601.parse(text))
        else { return nil }
        self = date
    }

    init(unixMilliseconds milliseconds: UInt64) {
        self.init(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
    }
}
