import SwiftUI

struct TodoPrioritySelector: View {
    nonisolated private static let row = "TodoPrioritySelector.row"

    @Binding var selection: TodoPriority

    @FocusState private var focusedPriority: TodoPriority?
    @State private var optionFrames: [TodoPriority: CGRect] = [:]
    @GestureState private var isScrubbing = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(TodoPriority.allCases, id: \.self) { priority in
                let isSelected = selection == priority

                Button(priority.title) {
                    selection = priority
                }
                .buttonStyle(
                    TodoPriorityButtonStyle(
                        priority: priority,
                        isSelected: isSelected,
                        isScrubbing: isScrubbing
                    )
                )
                .focused($focusedPriority, equals: priority)
                .accessibilityLabel(priority.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(Self.row))
                } action: { frame in
                    optionFrames[priority] = frame
                }
            }
        }
        .coordinateSpace(.named(Self.row))
        .simultaneousGesture(scrub)
        .onKeyPress(
            keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .home, .end],
            action: handleKeyPress
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Priority")
    }

    private var scrub: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.row))
            .updating($isScrubbing) { _, isScrubbing, _ in
                isScrubbing = true
            }
            .onChanged { drag in
                // the option under the pointer wins, so the pressed button firing on release agrees with the scrub.
                let distance = { (frame: CGRect) in max(frame.minX - drag.location.x, drag.location.x - frame.maxX) }
                if let nearest = optionFrames.min(by: { distance($0.value) < distance($1.value) }) {
                    selection = nearest.key
                }
            }
    }

    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        let destination: TodoPriority
        switch keyPress.key {
        case .leftArrow, .upArrow:
            destination = selection.cycled(by: -1)
        case .rightArrow, .downArrow:
            destination = selection.cycled(by: 1)
        case .home:
            destination = TodoPriority.allCases.first!
        case .end:
            destination = TodoPriority.allCases.last!
        default:
            return .ignored
        }
        selection = destination
        focusedPriority = destination
        return .handled
    }
}

private extension TodoPriority {
    func cycled(by offset: Int) -> Self {
        let cases = Self.allCases
        let index = cases.firstIndex(of: self)!
        return cases[(index + offset + cases.count) % cases.count]
    }
}

private struct TodoPriorityButtonStyle: ButtonStyle {
    let priority: TodoPriority
    let isSelected: Bool
    let isScrubbing: Bool

    func makeBody(configuration: Configuration) -> some View {
        TodoPriorityOption(
            priority: priority,
            configuration: configuration,
            isSelected: isSelected,
            isScrubbing: isScrubbing
        )
        .motionAnimation(.spring(response: 0.42, dampingFraction: 0.86), value: isSelected)
    }
}

private struct TodoPriorityOption: View, Animatable {
    let priority: TodoPriority
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    let isScrubbing: Bool
    var progress: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    init(priority: TodoPriority, configuration: ButtonStyleConfiguration, isSelected: Bool, isScrubbing: Bool) {
        self.priority = priority
        self.configuration = configuration
        self.isSelected = isSelected
        self.isScrubbing = isScrubbing
        progress = isSelected ? 1 : 0
    }

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let iconOpacity = smoothStep((progress - 0.2) / 0.4)
        // a scrub pins hover and press to the option it started on, so feedback waits for the scrub to end.
        let showsFeedback = !isSelected && !isScrubbing
        let isPressed = showsFeedback && configuration.isPressed
        let isHighlighted = showsFeedback && (isHovered || configuration.isPressed)
        // feedback enters quickly and settles back with a slight overshoot.
        let fade = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: isHighlighted ? 0.12 : 0.16)
        let scale =
            isHighlighted
            ? Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.12)
            : .timingCurve(0.34, 1.36, 0.64, 1, duration: 0.16)

        TodoPriorityMorphLayout(progress: progress) {
            Capsule()
                .fill(.white.opacity(0.1 * smoothStep(progress / 0.4)))

            ZStack {
                Circle()
                    .fill(.primary)
                    .animation(fade) { $0.opacity(isHighlighted ? 0.36 : 0.28) }
                    .animation(scale) { $0.scaleEffect(isPressed && !reduceMotion ? 0.85 : 1) }
                    .opacity(1 - smoothStep((progress - 0.25) / 0.3))

                Image(systemName: priority.symbolName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(priority.color)
                    .opacity(iconOpacity)
                    .blur(radius: (1 - iconOpacity) * 1.5)
            }
            .frame(width: TodoPriorityMorphLayout.iconSize, height: TodoPriorityMorphLayout.iconSize)
            .scaleEffect(
                lerp(TodoPriorityMorphLayout.dotDiameter / TodoPriorityMorphLayout.iconSize, 1, progress)
            )

            configuration.label
                .font(.system(size: 10, weight: .medium))
                .tracking(-0.1)
                .fixedSize()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .clipped()
                .opacity(smoothStep((progress - 0.5) / 0.45))
        }
        .background {
            Circle()
                .fill(.white.opacity(0.06))
                .frame(width: TodoPriorityMorphLayout.hitSize, height: TodoPriorityMorphLayout.hitSize)
                .animation(fade) { $0.opacity(isHighlighted ? 1 : 0) }
                .animation(scale) {
                    $0.scaleEffect(reduceMotion ? 1 : isPressed ? 0.94 : isHighlighted ? 1 : 0.9)
                }
        }
        .contentShape(.capsule)
        .onPointerHover { isHovered = $0 }
    }
}

private struct TodoPriorityMorphLayout: Layout {
    static let hitSize: CGFloat = 22
    static let dotDiameter: CGFloat = 6
    static let pillHeight: CGFloat = 22
    static let iconSize: CGFloat = 14
    static let leadingPadding: CGFloat = 6
    static let iconGap: CGFloat = 4
    static let trailingPadding: CGFloat = 8
    static let labelLeading = leadingPadding + iconSize + iconGap

    let progress: CGFloat

    func sizeThatFits(
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) -> CGSize {
        CGSize(
            width: lerp(Self.hitSize, pillWidth(for: subviews), progress),
            height: Self.pillHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        let surfaceSize = CGSize(
            width: lerp(Self.dotDiameter, pillWidth(for: subviews), progress),
            height: lerp(Self.dotDiameter, Self.pillHeight, progress)
        )
        let surface = CGRect(
            origin: CGPoint(
                x: bounds.minX + (Self.hitSize - Self.dotDiameter) * (1 - progress) / 2,
                y: bounds.midY - surfaceSize.height / 2
            ),
            size: surfaceSize
        )
        subviews[0].place(at: surface.origin, proposal: ProposedViewSize(surface.size))

        subviews[1].place(
            at: CGPoint(
                x: surface.minX + lerp(Self.dotDiameter / 2, Self.leadingPadding + Self.iconSize / 2, progress),
                y: surface.midY
            ),
            anchor: .center,
            proposal: ProposedViewSize(width: Self.iconSize, height: Self.iconSize)
        )

        let labelX = surface.minX + lerp(Self.dotDiameter / 2, Self.labelLeading, progress)
        subviews[2].place(
            at: CGPoint(x: labelX, y: surface.minY),
            proposal: ProposedViewSize(width: surface.maxX - labelX, height: surface.height)
        )
    }

    private func pillWidth(for subviews: Subviews) -> CGFloat {
        Self.labelLeading + subviews[2].sizeThatFits(.unspecified).width + Self.trailingPadding
    }
}

private func smoothStep(_ value: CGFloat) -> CGFloat {
    let value = min(max(value, 0), 1)
    return value * value * (3 - 2 * value)
}

private func lerp(_ start: CGFloat, _ end: CGFloat, _ progress: CGFloat) -> CGFloat {
    start + (end - start) * progress
}
