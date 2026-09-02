import AppKit
import Shimmer
import SwiftUI

struct PanelPagesView: View {
    @Environment(UsageModel.self) private var usageModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedPage = PanelPage.usage
    @State private var scrollTarget: PanelPage? = .usage

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(PanelPage.allCases, id: \.self) { page in
                    Group {
                        switch page {
                        case .usage:
                            ZStack(alignment: .top) {
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
                            .animation(
                                reduceMotion ? nil : .smooth(duration: 0.35),
                                value: usageModel.snapshot != nil
                            )
                        case .inbox:
                            // the usage page sets the panel height; the inbox fills it and scrolls inside
                            Color.clear.overlay { InboxView() }
                        }
                    }
                    .containerRelativeFrame(.horizontal)
                    .environment(\.isSelectedPanelPage, page == selectedPage)
                    .id(page)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        .scrollPosition(id: $scrollTarget)
        .onScrollTargetVisibilityChange(idType: PanelPage.self) { visiblePages in
            if let page = visiblePages.first {
                selectedPage = page
            }
        }
        .overlay(alignment: .bottom) {
            PanelPageIndicator(selectedPage: selectedPage, onSelect: navigate)
                .padding(.bottom, 6)
        }
        .background {
            ShiftScrollWheelMonitor(onStep: move)
        }
        .onChange(of: selectedPage) {
            if selectedPage != .inbox {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }

    private func move(_ direction: PanelPageDirection) {
        guard let destination = PanelPage(rawValue: selectedPage.rawValue + direction.rawValue)
        else {
            return
        }
        navigate(to: destination)
    }

    private func navigate(to page: PanelPage) {
        guard page != selectedPage else {
            return
        }
        selectedPage = page
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
            scrollTarget = page
        }
    }
}

/// Whether the enclosing pager page is the selected one; mounted but unselected pages drop
/// presentation state such as popovers here.
extension EnvironmentValues {
    @Entry var isSelectedPanelPage = true
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let selectedPage: PanelPage
    let onSelect: (PanelPage) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PanelPage.allCases, id: \.self) { page in
                let isSelected = selectedPage == page

                Button {
                    onSelect(page)
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.secondary)

                        if isSelected {
                            Circle()
                                .fill(Color.white)
                                .transition(
                                    .asymmetric(insertion: .identity, removal: .opacity)
                                )
                        }
                    }
                    .frame(width: 5, height: 5)
                    .frame(width: 14, height: 14)
                    .contentShape(.rect)
                    .animation(
                        reduceMotion ? nil : .easeOut(duration: 0.2),
                        value: isSelected
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(page.accessibilityLabel)
                .accessibilityValue(isSelected ? "Current page" : "")
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
                    guard let window = view?.window, event.window === window,
                        event.modifierFlags.intersection([
                            .shift, .control, .option, .command,
                        ]) == .shift,
                        event.phase.isEmpty, event.momentumPhase.isEmpty
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
