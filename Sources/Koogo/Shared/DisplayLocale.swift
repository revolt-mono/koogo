import Foundation

/// scene locale controls swiftui number and date text; styles producing strings must carry the display locale themselves.
extension Locale {
    static let display = Locale(identifier: "en_US")
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
