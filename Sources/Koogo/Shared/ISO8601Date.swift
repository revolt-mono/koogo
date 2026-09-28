import Foundation

extension Date {
    /// Parses an ISO 8601 timestamp with or without fractional seconds.
    init?(iso8601 text: String) {
        guard
            let date = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
                ?? (try? Date.ISO8601FormatStyle().parse(text))
        else { return nil }
        self = date
    }
}
