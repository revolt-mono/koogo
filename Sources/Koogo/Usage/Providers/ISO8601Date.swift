import Foundation

extension Date {
    private static let iso8601 = ISO8601FormatStyle()

    /// reads `yyyy-mm-ddThh:mm:ss[.fraction](Z|±hh:mm)` directly for years from 1600 and offsets within ±18:00;
    /// foundation parses everything else.
    init?(iso8601 text: some Collection<UInt8>) {
        let parsed =
            text.withContiguousStorageIfAvailable(Self.rfc3339) ?? Array(text).withUnsafeBufferPointer(Self.rfc3339)
        guard
            let date = parsed
                ?? String(validating: text, as: UTF8.self).flatMap({ try? Self.iso8601.parse($0) })
        else {
            return nil
        }
        self = date
    }

    init(unixMilliseconds milliseconds: UInt64) {
        self.init(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
    }

    private static func rfc3339(_ text: UnsafeBufferPointer<UInt8>) -> Date? {
        guard let year = text.number(0..<4, in: 1_600...9_999), text.has("-", at: 4),
            let month = text.number(5..<7, in: 1...12), text.has("-", at: 7),
            let day = text.number(8..<10, in: 1...daysInMonth(month, year: year)), text.has("T", at: 10),
            let hour = text.number(11..<13, in: 0...23), text.has(":", at: 13),
            let minute = text.number(14..<16, in: 0...59), text.has(":", at: 16),
            let second = text.number(17..<19, in: 0...59)
        else {
            return nil
        }

        var zoneStart = 19
        var fraction = 0.0
        if text.has(".", at: zoneStart) {
            let digits = text[(zoneStart + 1)...].prefix { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }
            guard (1...9).contains(digits.count), let value = text.number(digits.indices, in: 0...999_999_999) else {
                return nil
            }
            fraction = Double(value) / pow(10, Double(digits.count))
            zoneStart = digits.endIndex
        }
        guard let offset = zoneOffset(text, from: zoneStart) else {
            return nil
        }

        let seconds = daysSince1970(year: year, month: month, day: day) * 86_400 + hour * 3_600 + minute * 60 + second
        // foundation adds the fraction to seconds since the reference date; adding it earlier rounds differently.
        let whole = TimeInterval(seconds - offset) - Date.timeIntervalBetween1970AndReferenceDate
        return Date(timeIntervalSinceReferenceDate: whole + fraction)
    }

    /// seconds east of utc for a `Z` or `±hh:mm` zone that ends the text.
    private static func zoneOffset(_ text: UnsafeBufferPointer<UInt8>, from start: Int) -> Int? {
        if text.has("Z", at: start) {
            return start + 1 == text.count ? 0 : nil
        }
        guard text.has("+", at: start) || text.has("-", at: start), start + 6 == text.count,
            let hours = text.number(start + 1..<start + 3, in: 0...18), text.has(":", at: start + 3),
            let minutes = text.number(start + 4..<start + 6, in: 0...59), hours < 18 || minutes == 0
        else {
            return nil
        }
        return (hours * 3_600 + minutes * 60) * (text.has("-", at: start) ? -1 : 1)
    }

    private static func daysInMonth(_ month: Int, year: Int) -> Int {
        switch month {
        case 2: year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400)) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// proleptic gregorian day count, after howard hinnant's `days_from_civil`.
    private static func daysSince1970(year: Int, month: Int, day: Int) -> Int {
        let year = month <= 2 ? year - 1 : year
        let era = year / 400
        let yearOfEra = year - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}

extension UnsafeBufferPointer<UInt8> {
    /// the decimal digits in `range`, when every byte is a digit and the value is in `valid`.
    fileprivate func number(_ range: Range<Int>, in valid: ClosedRange<Int>) -> Int? {
        guard range.upperBound <= count else {
            return nil
        }
        var value = 0
        for byte in self[range] {
            guard (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) else {
                return nil
            }
            value = value * 10 + Int(byte - UInt8(ascii: "0"))
        }
        return valid.contains(value) ? value : nil
    }

    fileprivate func has(_ ascii: Unicode.Scalar, at index: Int) -> Bool {
        index < count && self[index] == UInt8(ascii: ascii)
    }
}
