import AppKit
import SwiftUI

struct QuickActionsControl: View {
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Text("Quick Actions")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 32)
            .contentShape(.rect)
            .background(
                Color.white.opacity(isPresented ? 0.06 : 0),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .background {
            QuickActionsPopover(isPresented: $isPresented)
                .allowsHitTesting(false)
        }
        .onDisappear {
            isPresented = false
        }
    }
}

private struct QuickActionsPopover: NSViewRepresentable {
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    func makeNSView(context _: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ anchor: NSView, context: Context) {
        context.coordinator.update(isPresented: $isPresented, relativeTo: anchor)
    }

    static func dismantleNSView(_: NSView, coordinator: Coordinator) {
        coordinator.popover.close()
    }

    @MainActor
    final class Coordinator: NSObject, NSPopoverDelegate {
        let popover = NSPopover()
        private var isPresented: Binding<Bool>

        init(isPresented: Binding<Bool>) {
            self.isPresented = isPresented
            super.init()

            let hostingController = NSHostingController(rootView: QuickActionsPopoverContent())
            hostingController.sizingOptions = .preferredContentSize
            popover.contentViewController = hostingController
            popover.behavior = .semitransient
            // NSPopover's native transition cannot reverse, so animation would queue rapid toggles.
            popover.animates = false
            popover.delegate = self
        }

        func update(isPresented: Binding<Bool>, relativeTo anchor: NSView) {
            self.isPresented = isPresented
            let shouldShow = isPresented.wrappedValue
            guard shouldShow != popover.isShown else {
                return
            }

            if shouldShow {
                popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
            } else {
                popover.close()
            }
        }

        func popoverDidClose(_: Notification) {
            if isPresented.wrappedValue {
                isPresented.wrappedValue = false
            }
        }
    }
}
