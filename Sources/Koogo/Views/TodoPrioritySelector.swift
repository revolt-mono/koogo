import SwiftUI

extension TodoPriority {
    var color: Color {
        switch self {
        case .backlog: .secondary
        case .normal: .blue
        case .urgent: .red
        }
    }
}

private extension TodoPriority {
    var previous: Self {
        switch self {
        case .backlog: .urgent
        case .normal: .backlog
        case .urgent: .normal
        }
    }

    var next: Self {
        switch self {
        case .backlog: .normal
        case .normal: .urgent
        case .urgent: .backlog
        }
    }
}

struct TodoPrioritySpring {
    private static let omega = 2 * CGFloat.pi / 0.42
    private static let stiffness = omega * omega
    private static let damping = 2 * 0.86 * omega

    private(set) var progress: CGFloat
    private(set) var velocity: CGFloat
    private(set) var target: CGFloat

    var isActive: Bool {
        progress != target || velocity != 0
    }

    init(isSelected: Bool) {
        let target: CGFloat = isSelected ? 1 : 0
        progress = target
        velocity = 0
        self.target = target
    }

    mutating func retarget(isSelected: Bool) {
        target = isSelected ? 1 : 0
    }

    mutating func snap() {
        progress = target
        velocity = 0
    }

    mutating func advance(by duration: CGFloat) -> Bool {
        guard isActive else {
            return false
        }

        velocity +=
            (-Self.stiffness * (progress - target) - Self.damping * velocity) * duration
        progress += velocity * duration

        if abs(progress - target) < 0.001, abs(velocity) < 0.005 {
            snap()
            return false
        }
        return true
    }
}

struct TodoPrioritySelector: View {
    @Binding var selection: TodoPriority

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedPriority: TodoPriority?

    @State private var springs: [TodoPriority: TodoPrioritySpring]
    @State private var expandedWidths: [TodoPriority: CGFloat] = [:]
    @State private var lastFrame: ContinuousClock.Instant?

    init(selection: Binding<TodoPriority>) {
        _selection = selection
        _springs = State(
            initialValue: Dictionary(
                uniqueKeysWithValues: TodoPriority.allCases.map { priority in
                    (
                        priority,
                        TodoPrioritySpring(isSelected: priority == selection.wrappedValue)
                    )
                }
            )
        )
    }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || !springsAreActive)) { timeline in
            HStack(spacing: 4) {
                ForEach(TodoPriority.allCases, id: \.self) { priority in
                    let isSelected = selection == priority

                    Button {
                        selection = priority
                    } label: {
                        TodoPriorityOption(
                            priority: priority,
                            pillWidth: expandedWidths[priority] ?? 20,
                            isSelected: isSelected,
                            progress: springs[priority]?.progress ?? (isSelected ? 1 : 0)
                        ) { width in
                            recordExpandedWidth(width, for: priority)
                        }
                    }
                    .buttonStyle(TodoPriorityButtonStyle())
                    .focused($focusedPriority, equals: priority)
                    .accessibilityLabel(priority.rawValue)
                    .accessibilityValue(isSelected ? "Selected priority" : "")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .opacity(widthsAreReady ? 1 : 0)
            .accessibilityHidden(!widthsAreReady)
            .onChange(of: timeline.date, advanceSprings)
        }
        .onKeyPress(
            keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .home, .end],
            action: handleKeyPress
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Priority")
        .onChange(of: selection, retargetSprings)
        .onChange(of: reduceMotion) {
            if reduceMotion {
                retargetSprings()
            }
        }
        .onDisappear {
            lastFrame = nil
        }
    }

    private var widthsAreReady: Bool {
        expandedWidths.count == TodoPriority.allCases.count
    }

    private var springsAreActive: Bool {
        springs.values.contains(where: \.isActive)
    }

    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        let destination: TodoPriority
        switch keyPress.key {
        case .leftArrow, .upArrow:
            destination = selection.previous
        case .rightArrow, .downArrow:
            destination = selection.next
        case .home:
            destination = .backlog
        case .end:
            destination = .urgent
        default:
            return .ignored
        }
        selection = destination
        focusedPriority = destination
        return .handled
    }

    private func recordExpandedWidth(_ width: CGFloat, for priority: TodoPriority) {
        guard width > 0, expandedWidths[priority] != width else {
            return
        }

        let wasReady = widthsAreReady
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            expandedWidths[priority] = width
        }

        if !wasReady, widthsAreReady {
            retargetSprings()
        }
    }

    private func retargetSprings() {
        let wasActive = springsAreActive
        let shouldSnap = reduceMotion || !widthsAreReady
        var springs = springs
        for priority in TodoPriority.allCases {
            springs[priority]?.retarget(isSelected: priority == selection)
            if shouldSnap {
                springs[priority]?.snap()
            }
        }

        self.springs = springs
        if shouldSnap || !wasActive {
            lastFrame = nil
        }
    }

    private func advanceSprings() {
        let now = ContinuousClock.now
        let duration: CGFloat
        if let lastFrame {
            let elapsed = (now - lastFrame).components
            duration = min(
                CGFloat(elapsed.seconds)
                    + CGFloat(elapsed.attoseconds) / 1_000_000_000_000_000_000,
                0.032
            )
        } else {
            duration = 1.0 / 60
        }
        self.lastFrame = now

        var springs = springs
        var remainsActive = false
        for priority in TodoPriority.allCases {
            guard var spring = springs[priority] else {
                continue
            }
            remainsActive = spring.advance(by: duration) || remainsActive
            springs[priority] = spring
        }
        self.springs = springs

        if !remainsActive {
            lastFrame = nil
        }
    }
}

private struct TodoPriorityOption: View {
    let priority: TodoPriority
    let pillWidth: CGFloat
    let isSelected: Bool
    let progress: CGFloat
    let onMeasure: (CGFloat) -> Void

    @State private var isHovered = false

    var body: some View {
        TodoPriorityMorph(
            priority: priority,
            pillWidth: pillWidth,
            showsHover: isHovered && !isSelected,
            progress: progress
        )
        .onHover { isHovered = $0 }
        .background {
            expandedLabel
                .fixedSize()
                .hidden()
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.width
                } action: { width in
                    onMeasure(width)
                }
        }
    }

    private var expandedLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(priority.color)

            Text(priority.rawValue)
                .font(.system(size: 9, weight: .medium))
                .tracking(-0.09)
                .foregroundStyle(.primary)
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .frame(height: 22)
    }
}

private struct TodoPriorityMorph: View {
    let priority: TodoPriority
    let pillWidth: CGFloat
    let showsHover: Bool
    let progress: CGFloat

    var body: some View {
        let morphProgress = min(max(progress, -0.08), 1.12)
        let clampedProgress = Self.clamp(morphProgress)
        let itemWidth = Self.lerp(20, pillWidth, morphProgress)
        let backgroundWidth = max(3, Self.lerp(5, pillWidth, morphProgress))
        let backgroundHeight = max(3, Self.lerp(5, 22, morphProgress))
        let backgroundLeading = 7.5 * (1 - morphProgress)
        let glyphCenter = Self.lerp(2.5, 11, morphProgress)
        let glyphScale = Self.lerp(0.5, 1, morphProgress)
        let dotOpacity = 1 - Self.smooth((clampedProgress - 0.25) / 0.3)
        let iconProgress = Self.smooth((clampedProgress - 0.2) / 0.4)
        let labelProgress = Self.smooth((clampedProgress - 0.5) / 0.45)
        let labelLeading = Self.lerp(2.5, 20, morphProgress)

        ZStack(alignment: .leading) {
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 20, height: 20)
                .opacity(showsHover ? 1 : 0)

            Capsule()
                .fill(Color.white.opacity(0.08 * Self.smooth(clampedProgress / 0.4)))
                .frame(width: backgroundWidth, height: backgroundHeight)
                .offset(x: backgroundLeading)

            ZStack {
                Circle()
                    .fill(Color.primary.opacity(showsHover ? 0.24 : 0.16))
                    .opacity(dotOpacity)

                Image(systemName: "circle.dashed")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(priority.color)
                    .opacity(iconProgress)
                    .blur(radius: 1 - iconProgress)
            }
            .frame(width: 10, height: 10)
            .scaleEffect(glyphScale)
            .offset(x: backgroundLeading + glyphCenter - 5)

            ZStack(alignment: .leading) {
                Text(priority.rawValue)
                    .font(.system(size: 9, weight: .medium))
                    .tracking(-0.09)
                    .foregroundStyle(.primary)
                    .fixedSize()
                    .opacity(labelProgress)
                    .offset(x: labelLeading)
            }
            .frame(width: backgroundWidth, height: backgroundHeight, alignment: .leading)
            .clipShape(.capsule)
            .offset(x: backgroundLeading)
        }
        .frame(width: itemWidth, height: 22, alignment: .leading)
        .contentShape(.capsule)
    }

    private static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

    private static func smooth(_ value: CGFloat) -> CGFloat {
        let value = clamp(value)
        return value * value * (3 - 2 * value)
    }

    private static func lerp(
        _ initialValue: CGFloat,
        _ destination: CGFloat,
        _ progress: CGFloat
    ) -> CGFloat {
        initialValue + (destination - initialValue) * progress
    }
}

private struct TodoPriorityButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.94)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
