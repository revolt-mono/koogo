import Foundation

/// scene locale controls swiftui number and date text; styles producing strings must carry the display locale themselves.
extension Locale {
    static let display = Locale(identifier: "en_US")
}

extension FormatStyle where Self == Date.FormatStyle {
    static func display(date: Date.FormatStyle.DateStyle, time: Date.FormatStyle.TimeStyle) -> Self {
        Date.FormatStyle(date: date, time: time, locale: .display)
    }
}

extension FormatStyle where Self == Duration.UnitsFormatStyle {
    static func displayUnits(allowed: Set<Duration.UnitsFormatStyle.Unit>) -> Self {
        Duration.UnitsFormatStyle(
            allowedUnits: allowed,
            width: .narrow,
            maximumUnitCount: 2,
            fractionalPart: .hide(rounded: .towardZero)
        )
        .locale(.display)
    }
}

extension FormatStyle where Self == Duration.TimeFormatStyle {
    static func displayTime(pattern: Duration.TimeFormatStyle.Pattern) -> Self {
        Duration.TimeFormatStyle(pattern: pattern).locale(.display)
    }
}
