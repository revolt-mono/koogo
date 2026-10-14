import Foundation

extension Date {
    /// Parses fractional seconds too, though it never writes them.
    private static let iso8601 = ISO8601FormatStyle()

    init?(iso8601 text: String) {
        guard let date = try? Self.iso8601.parse(text) else {
            return nil
        }
        self = date
    }

    init(unixMilliseconds milliseconds: UInt64) {
        self.init(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
    }
}
