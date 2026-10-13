struct InputRules: Equatable {
    enum NotchMode: UInt32, CaseIterable {
        case standard
        case optionPrecision
        /// One line; Option raises it to the wheel step and is hidden, so terminals don't read alt-scroll.
        case lineByLine
    }

    var wheelStep: WheelStep
    var direction: ScrollDirection
    var notchMode: NotchMode
    var isLookUpEnabled: Bool

    func step(for notch: WheelNotch, isOptionHeld: Bool) -> ScrollStep {
        let (lines, stripsOption): (Int32, Bool) =
            switch (notchMode, isOptionHeld) {
            case (.standard, _), (.optionPrecision, false): (wheelStep.lines, false)
            case (.optionPrecision, true): (1, true)
            case (.lineByLine, false): (1, false)
            case (.lineByLine, true): (wheelStep.lines, true)
            }
        let sign: Int32 =
            switch direction {
            case .standard: -1
            case .natural: 1
            }
        return ScrollStep(axis: notch.axis, lines: sign * notch.direction.rawValue * lines, stripsOption: stripsOption)
    }
}

extension InputRules {
    /// The frontmost app approximates the scroll target: scrolls reach the window under the pointer, but resolving that would add a lookup to every notch.
    init(_ settings: MouseSettings, frontmostApp: String?) {
        let notchMode: NotchMode =
            if let frontmostApp, settings.lineByLineApps.contains(frontmostApp) {
                .lineByLine
            } else if settings.isOptionPrecisionEnabled {
                .optionPrecision
            } else {
                .standard
            }
        self.init(
            wheelStep: settings.wheelStep,
            direction: settings.direction,
            notchMode: notchMode,
            isLookUpEnabled: settings.isLookUpEnabled
        )
    }
}

struct WheelNotch: Equatable {
    enum Axis: Equatable {
        case vertical
        case horizontal
    }

    enum Direction: Int32 {
        case negative = -1
        case positive = 1
    }

    let axis: Axis
    let direction: Direction
}

extension WheelNotch {
    init?(verticalDelta: Int64, horizontalDelta: Int64) {
        switch (verticalDelta.signum(), horizontalDelta.signum()) {
        case (-1, 0): self.init(axis: .vertical, direction: .negative)
        case (1, 0): self.init(axis: .vertical, direction: .positive)
        case (0, -1): self.init(axis: .horizontal, direction: .negative)
        case (0, 1): self.init(axis: .horizontal, direction: .positive)
        default: return nil
        }
    }
}

struct ScrollStep: Equatable {
    let axis: WheelNotch.Axis
    let lines: Int32
    let stripsOption: Bool
}
