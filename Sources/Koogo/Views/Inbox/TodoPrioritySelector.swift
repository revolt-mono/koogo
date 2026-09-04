import SwiftUI

extension TodoPriority {
    var title: String {
        rawValue.capitalized
    }

    var symbolName: String {
        switch self {
        case .backlog: "circle.dashed"
        case .normal: "circle"
        case .urgent: "exclamationmark.circle"
        }
    }

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

/// A row of dots where the selected priority morphs into a labeled pill.
struct TodoPrioritySelector: View {
    @Binding var selection: TodoPriority

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedPriority: TodoPriority?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(TodoPriority.allCases, id: \.self) { priority in
                let isSelected = selection == priority

                Button {
                    selection = priority
                } label: {
                    TodoPriorityOption(
                        priority: priority,
                        isSelected: isSelected,
                        progress: isSelected ? 1 : 0
                    )
                    // Inside the label so the morph animates even when the
                    // pressed button re-renders in its gesture's transaction.
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86),
                        value: isSelected
                    )
                }
                .buttonStyle(TodoPriorityButtonStyle())
                .focused($focusedPriority, equals: priority)
                .accessibilityLabel(priority.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .onKeyPress(
            keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .home, .end],
            action: handleKeyPress
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Priority")
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
}

private struct TodoPriorityButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct TodoPriorityOption: View, Animatable {
    let priority: TodoPriority
    let isSelected: Bool
    var progress: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let iconOpacity = smoothStep((progress - 0.2) / 0.4)
        let showsHover = isHovered && !isSelected

        TodoPriorityMorphLayout(progress: progress) {
            Capsule()
                .fill(.white.opacity(0.1 * smoothStep(progress / 0.4)))

            ZStack {
                Circle()
                    .fill(.primary.opacity(0.28))
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

            Text(priority.title)
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
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                    $0.opacity(showsHover ? 1 : 0).scaleEffect(showsHover ? 1 : 0.9)
                }
        }
        .contentShape(.capsule)
        .onHover { isHovered = $0 }
    }
}

/// Places surface, glyph, and label, in that subview order, along the
/// dot → pill morph. Reading the label's ideal width here avoids a
/// measurement round trip.
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
