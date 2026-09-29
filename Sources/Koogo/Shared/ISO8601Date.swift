import Foundation

extension Date {
    private static let fractionalISO8601 = ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let wholeISO8601 = ISO8601FormatStyle()

    /// Parses an ISO 8601 timestamp with or without fractional seconds.
    init?(iso8601 text: String) {
        guard
            let date = (try? Self.fractionalISO8601.parse(text))
                ?? (try? Self.wholeISO8601.parse(text))
        else { return nil }
        self = date
    }
}
