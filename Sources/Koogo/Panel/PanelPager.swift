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
}

/// A paging scroll across the pages, so a swipe moves the pages with the fingers and the system snaps them; a wheel click or a dot steps a whole page. The pages are built once up front and stay, so a swipe never builds or lays out a page. The usage page sets the height and the others fill it, so a switch never resizes the window.
struct PanelPager: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let maxHeight: CGFloat

    @State private var shown: PanelPage? = .usage
    @State private var usageHeight: CGFloat = 0
    @State private var slide = PageSlide()

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
                                    usageHeight = height
                                }
                        case .activity:
                            ActivityPage(isShown: shown == .activity)
                        case .inbox:
                            InboxPage()
                        }
                    }
                    .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
            .background { PageSlideAnchor(slide: slide) }
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $shown)
        .scrollIndicators(.never, axes: .horizontal)
        .frame(height: min(usageHeight, maxHeight))
        .overlay(alignment: .bottom) {
            PanelPageIndicator(shown: shown, onSelect: show)
                .padding(.bottom, 6)
        }
        .background {
            LocalEventMonitor(events: .scrollWheel) { event, view in
                guard let window = view.window, event.window === window else { return event }
                switch WheelPaging(event) {
                case .step(let step):
                    if let shown, let page = PanelPage(rawValue: shown.rawValue + step) { show(page) }
                    return nil
                case .drop:
                    return nil
                case .pass:
                    return event
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// The model jumps with animations off, or SwiftUI scrolls there on its own alongside the slide and costs twice the frames.
    private func show(_ page: PanelPage) {
        var jump = Transaction()
        jump.disablesAnimations = true
        withTransaction(jump) {
            shown = page
        }
        if !reduceMotion {
            slide.run(to: page)
        }
    }
}

/// Slides the clip view on the render server while the model jumps to the target page. A SwiftUI animation re-lays out every page on each frame it moves; this costs the main thread one update.
@MainActor
private final class PageSlide {
    weak var anchor: NSView?

    func run(to page: PanelPage) {
        guard let clip = anchor?.enclosingScrollView?.contentView, let layer = clip.layer else { return }
        let slide = CASpringAnimation(perceptualDuration: 0.3, bounce: 0)
        slide.keyPath = "bounds.origin.x"
        slide.fromValue = (layer.presentation() ?? layer).bounds.origin.x
        slide.toValue = CGFloat(page.rawValue) * clip.bounds.width
        layer.add(slide, forKey: "slide")
    }
}

private struct PageSlideAnchor: NSViewRepresentable {
    let slide: PageSlide

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        slide.anchor = view
        return view
    }

    func updateNSView(_: NSView, context: Context) {}
}

private struct PanelPageIndicator: View {
    let shown: PanelPage?
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
