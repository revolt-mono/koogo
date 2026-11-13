import Foundation

extension FormatStyle where Self == Date.FormatStyle {
  static func display(date: Date.FormatStyle.DateStyle, time: Date.FormatStyle.TimeStyle) -> Self {
    Date.FormatStyle(date: date, time: time, locale: .display)
  }
}
