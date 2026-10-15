import SwiftUI

/// swift charts and drawing groups incur large offscreen graphics allocations inside the glass panel.
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

extension CGFloat {
    func pixelSnapped(scale: CGFloat) -> CGFloat {
        (self * scale).rounded() / scale
    }
}
