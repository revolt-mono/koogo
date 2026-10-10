import SwiftUI

/// Bars on one baseline, each a fraction of the full height. A path rather than Swift Charts or a drawing group, which both re-render offscreen at about 100 MB of graphics memory per change inside the panel's glass window.
struct BarChart: Shape {
    private static let gap: CGFloat = 1

    var values: [Double]
    /// A fixed slot width shows the newest values that fit, filling from the left; nil spreads every value across the width.
    var slotWidth: CGFloat?
    var cornerRadius: CGFloat = 0
    let displayScale: CGFloat

    var animatableData: AnimatableValues {
        get { AnimatableValues(values) }
        set { values = newValue.values }
    }

    func path(in rect: CGRect) -> Path {
        let shown = if let slotWidth { values.suffix(Int(rect.width / slotWidth)) } else { values[...] }
        let slot = slotWidth ?? rect.width / CGFloat(values.count)
        var path = Path()
        for (index, value) in shown.enumerated() where value > 0 {
            let left = snapped(slot * CGFloat(index) + Self.gap / 2)
            let right = snapped(slot * CGFloat(index + 1) - Self.gap / 2)
            let height = max(rect.height * value, cornerRadius * 2)
            path.addRoundedRect(
                in: CGRect(x: rect.minX + left, y: rect.maxY - height, width: right - left, height: height),
                cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
            )
        }
        return path
    }

    private func snapped(_ offset: CGFloat) -> CGFloat {
        (offset * displayScale).rounded() / displayScale
    }
}

struct AnimatableValues: VectorArithmetic {
    private(set) var values: [Double]

    init(_ values: [Double]) {
        self.values = values
    }

    static let zero = Self([])

    var magnitudeSquared: Double {
        values.reduce(0) { $0 + $1 * $1 }
    }

    mutating func scale(by factor: Double) {
        values = values.map { $0 * factor }
    }

    static func + (lhs: Self, rhs: Self) -> Self {
        combine(lhs, rhs, +)
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        combine(lhs, rhs, -)
    }

    private static func combine(_ lhs: Self, _ rhs: Self, _ operation: (Double, Double) -> Double) -> Self {
        let count = max(lhs.values.count, rhs.values.count)
        func value(_ side: Self, _ index: Int) -> Double {
            index < side.values.count ? side.values[index] : 0
        }
        return Self((0..<count).map { operation(value(lhs, $0), value(rhs, $0)) })
    }
}
