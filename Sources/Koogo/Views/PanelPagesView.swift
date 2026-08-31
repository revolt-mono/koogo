import AppKit
import Shimmer
import SwiftUI

struct PanelPagesView: View {
    @Environment(UsageModel.self) private var usageModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let dismissInput: () -> Void

    @State private var visiblePage = PanelPage.usage

    private var pagePosition: Binding<PanelPage?> {
        Binding(
            get: { visiblePage },
            set: { page in
                if let page {
                    visiblePage = page
                }
            }
        )
    }

    init(dismissInput: @escaping () -> Void) {
        self.dismissInput = dismissInput
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(PanelPage.allCases, id: \.self) { page in
                    Group {
                        switch page {
                        case .usage:
                            Group {
                                if let snapshot = usageModel.snapshot {
                                    UsagePanelView(snapshot: snapshot)
                                        .transition(.blurReplace)
                                } else {
                                    Text("Parsing logs…")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.secondary)
                                        .shimmering(active: !reduceMotion)
                                        .frame(maxWidth: .infinity, minHeight: 96)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 24)
                                        .transition(.blurReplace)
                                }
                            }
                            .animation(.smooth(duration: 0.35), value: usageModel.snapshot != nil)
                        case .inbox:
                            InboxView(dismissInput: dismissInput)
                        }
                    }
                    .containerRelativeFrame(.horizontal)
                    .id(page)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        .scrollPosition(id: pagePosition)
        .onScrollGeometryChange(for: PanelPage?.self) { geometry in
            guard geometry.containerSize.width > 0 else {
                return nil
            }
            return PanelPage(
                rawValue: Int((geometry.contentOffset.x / geometry.containerSize.width).rounded())
            )
        } action: { _, page in
            if let page {
                visiblePage = page
            }
        }
        .overlay(alignment: .bottom) {
            PanelPageIndicator(selectedPage: visiblePage, onSelect: navigate)
                .padding(.bottom, 6)
        }
        .background {
            ShiftScrollWheelMonitor(onStep: move)
        }
        .onChange(of: visiblePage) {
            if visiblePage != .inbox {
                dismissInput()
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func move(_ direction: PanelPageDirection) {
        guard let destination = PanelPage(rawValue: visiblePage.rawValue + direction.rawValue) else {
            return
        }
        navigate(to: destination)
    }

    private func navigate(to page: PanelPage) {
        dismissInput()
        if reduceMotion {
            visiblePage = page
        } else {
            withAnimation(.smooth(duration: 0.3)) {
                visiblePage = page
            }
        }
    }
}

private enum PanelPageDirection: Int {
    case previous = -1
    case next = 1
}

private enum PanelPage: Int, CaseIterable, Hashable {
    case usage
    case inbox

    var accessibilityLabel: String {
        switch self {
        case .usage: "Usage"
        case .inbox: "Inbox"
        }
    }
}

private struct PanelPageIndicator: View {
    let selectedPage: PanelPage
    let onSelect: (PanelPage) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PanelPage.allCases, id: \.self) { page in
                Button {
                    onSelect(page)
                } label: {
                    Circle()
                        .fill(selectedPage == page ? Color.white : Color.secondary)
                        .frame(width: 5, height: 5)
                        .frame(width: 14, height: 14)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(page.accessibilityLabel)
                .accessibilityValue(selectedPage == page ? "Current page" : "")
            }
        }
        .padding(.horizontal, 4)
        .background(.black.opacity(0.22), in: Capsule())
    }
}

private struct ShiftScrollWheelMonitor: NSViewRepresentable {
    let onStep: (PanelPageDirection) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onStep: onStep)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.startMonitoring(view)
        return view
    }

    func updateNSView(_: NSView, context: Context) {
        context.coordinator.onStep = onStep
    }

    static func dismantleNSView(_: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    @MainActor
    final class Coordinator {
        var onStep: (PanelPageDirection) -> Void
        private var eventMonitor: Any?

        init(onStep: @escaping (PanelPageDirection) -> Void) {
            self.onStep = onStep
        }

        func startMonitoring(_ view: NSView) {
            eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: .scrollWheel,
                handler: { [self, weak view] event in
                    let modifiers = event.modifierFlags.intersection([
                        .shift, .control, .option, .command,
                    ])
                    guard let window = view?.window, event.window === window,
                        modifiers == .shift, event.phase.isEmpty, event.momentumPhase.isEmpty
                    else {
                        return event
                    }

                    let delta =
                        event.scrollingDeltaY != 0
                        ? event.scrollingDeltaY
                        : -event.scrollingDeltaX
                    guard delta != 0 else {
                        return event
                    }
                    onStep(delta > 0 ? .next : .previous)
                    return nil
                }
            )
        }

        func stopMonitoring() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
        }
    }
}
