import Foundation

/// User-visible numbers and dates render in one locale. A scene root sets this as the SwiftUI locale, which `Text(_:format:)` reads over a style's own; a style that renders to a `String` carries it itself.
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
