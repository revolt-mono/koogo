import AppKit
import SwiftUI

enum PanelPage: Int, CaseIterable {
    case usage
    case activity
    case inbox

    var accessibilityLabel: String {
        switch self {
        case .usage: "Usage"
        case .activity: "Activity"
        case .inbox: "Inbox"
        }
    }

    func stepped(_ step: PageStep) -> PanelPage? {
        PanelPage(rawValue: rawValue + (step == .forward ? 1 : -1))
    }
}

/// Shows one page at a time, so a page's work runs only while it is on screen. The usage page, shown first, sets the height and the others fill it, so a switch never resizes the window.
struct PanelPager: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let maxHeight: CGFloat

    @State private var shown = PanelPage.usage
    @State private var lastStep = PageStep.forward
    @State private var steps = PageStepRecognizer()
    /// A returning usage page measures a short first pass before it settles, so the pager follows its height only outside a slide.
    @State private var usageHeight: CGFloat = 0
    @State private var pageHeight: CGFloat = 0
    @State private var isSliding = false

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                switch shown {
                case .usage:
                    UsagePage(maxHeight: maxHeight)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height.rounded()
                        } action: { height in
                            usageHeight = height
                            if !isSliding { pageHeight = height }
                        }
                case .activity:
                    ActivityPage()
                case .inbox:
                    InboxPage()
                }
            }
            .transition(
                .asymmetric(insertion: .move(edge: lastStep.entryEdge), removal: .move(edge: lastStep.exitEdge))
            )
        }
        .frame(height: min(pageHeight, maxHeight))
        .overlay(alignment: .bottom) {
            PanelPageIndicator(shown: shown, onSelect: show)
                .padding(.bottom, 6)
        }
        .background {
            LocalEventMonitor(events: .scrollWheel) { event, view in
                guard let window = view.window, event.window === window, let scroll = PageScroll(event) else {
                    return event
                }
                switch steps.receive(scroll) {
                case .step(let step):
                    if let page = shown.stepped(step) { show(page) }
                    return nil
                case .consumed:
                    return nil
                case .ignored:
                    return event
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func show(_ page: PanelPage) {
        guard page != shown else { return }
        lastStep = page.rawValue > shown.rawValue ? .forward : .backward
        isSliding = true
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
            shown = page
        } completion: {
            guard shown == page else { return }
            isSliding = false
            pageHeight = usageHeight
        }
    }
}

extension PageStep {
    fileprivate var entryEdge: Edge { self == .forward ? .trailing : .leading }
    fileprivate var exitEdge: Edge { self == .forward ? .leading : .trailing }
}

private struct PanelPageIndicator: View {
    let shown: PanelPage
    let onSelect: (PanelPage) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PanelPage.allCases, id: \.self) { page in
                let isShown = shown == page

                Button {
                    onSelect(page)
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.secondary)

                        if isShown {
                            Circle()
                                .fill(Color.white)
                                .transition(.asymmetric(insertion: .identity, removal: .opacity))
                        }
                    }
                    .frame(width: 5, height: 5)
                    .frame(width: 14, height: 14)
                    .contentShape(.rect)
                    .motionAnimation(.easeOut(duration: 0.2), value: isShown)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(page.accessibilityLabel)
                .accessibilityValue(isShown ? "Current page" : "")
            }
        }
        .padding(.horizontal, 4)
        .glassEffect(.regular, in: Capsule())
    }
}
