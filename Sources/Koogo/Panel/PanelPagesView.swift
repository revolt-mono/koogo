import AppKit
import SwiftUI

struct PanelPagesView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Screen space left for the pages; the usage page fits its provider cards into it.
    let maxHeight: CGFloat

    @State private var selectedPage = PanelPage.usage
    @State private var scrollTarget: PanelPage? = .usage
    @State private var usageContentHeight: CGFloat = 0

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(PanelPage.allCases, id: \.self) { page in
                    Group {
                        switch page {
                        case .usage:
                            UsagePage(maxHeight: maxHeight)
                                .fixedSize(horizontal: false, vertical: true)
                                .onGeometryChange(for: CGFloat.self) { proxy in
                                    proxy.size.height.rounded()
                                } action: { height in
                                    usageContentHeight = height
                                }
                        case .inbox:
                            InboxView()
                        }
                    }
                    .containerRelativeFrame(.horizontal)
                    .environment(\.isSelectedPanelPage, page == selectedPage)
                    .id(page)
                }
            }
            .scrollTargetLayout()
        }
        // Scoped to the pager's own axis so vertical scrolling inside pages keeps its scroller.
        .scrollIndicators(.never, axes: .horizontal)
        .frame(height: min(usageContentHeight, maxHeight))
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
            LocalEventMonitor(events: .scrollWheel) { event, view in
                guard let window = view.window, event.window === window,
                    event.modifierFlags.intersection([.shift, .control, .option, .command]) == .shift,
                    event.phase.isEmpty, event.momentumPhase.isEmpty
                else {
                    return event
                }

                let delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : -event.scrollingDeltaX
                guard delta != 0 else {
                    return event
                }
                if let destination = PanelPage(rawValue: selectedPage.rawValue + (delta > 0 ? 1 : -1)) {
                    navigate(to: destination)
                }
                return nil
            }
        }
        // Leaving a page drops keyboard focus so an off-screen text field cannot keep receiving keys.
        .onChange(of: selectedPage) {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
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
                    .motionAnimation(.easeOut(duration: 0.2), value: isSelected)
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
