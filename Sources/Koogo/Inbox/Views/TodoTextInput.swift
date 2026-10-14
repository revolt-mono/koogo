import AppKit
import Carbon.HIToolbox
import SwiftUI

struct TodoTextInput: NSViewRepresentable {
    static let font: NSFont = {
        let base = NSFont.systemFont(ofSize: 11, weight: .medium)
        return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: base.pointSize) } ?? base
    }()
    static let textInset = NSSize(width: 5, height: 6)
    static let maxHeight: CGFloat = 56

    enum Mode {
        case composing
        case editing
    }

    @Binding var text: String
    let mode: Mode
    let onSubmit: () -> Void
    var onCancel: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = context.coordinator.textView
        textView.font = Self.font
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainerInset = Self.textInset
        textView.textContainer?.lineFragmentPadding = 0

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = context.coordinator.textView
        textView.onSubmit = onSubmit
        textView.onCancel = onCancel
        if textView.string != text {
            textView.string = text
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        if case .editing = mode, !context.coordinator.didRequestFocus {
            context.coordinator.didRequestFocus = true
            // Wait for the context menu to close before taking focus.
            Task {
                try? await Task.sleep(for: .milliseconds(50))
                scrollView.window?.makeFirstResponder(textView)
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView _: NSScrollView, context: Context) -> CGSize? {
        let textView = context.coordinator.textView
        guard case .editing = mode, let width = proposal.width, width > 0,
            let layoutManager = textView.layoutManager,
            let container = textView.textContainer
        else {
            return nil
        }
        container.size.width = width - Self.textInset.width * 2
        layoutManager.ensureLayout(for: container)
        let lineHeight = layoutManager.defaultLineHeight(for: Self.font)
        let textHeight = max(layoutManager.usedRect(for: container).height, lineHeight)
        return CGSize(width: width, height: min(textHeight + Self.textInset.height * 2, Self.maxHeight))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        fileprivate let textView = TodoTextView(usingTextLayoutManager: false)
        var didRequestFocus = false

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_: Notification) {
            text.wrappedValue = textView.string
        }
    }
}

private final class TodoTextView: NSTextView {
    var onSubmit: () -> Void = {}
    var onCancel: () -> Void = {}

    override func keyDown(with event: NSEvent) {
        guard !hasMarkedText() else {
            super.keyDown(with: event)
            return
        }

        // TextKit finishes dispatching a key event after keyDown returns, so callbacks wait a turn.
        let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        switch (event.keyCode, modifiers) {
        case (UInt16(kVK_Return), .shift), (UInt16(kVK_ANSI_KeypadEnter), .shift):
            insertNewlineIgnoringFieldEditor(nil)
        case (UInt16(kVK_Return), []), (UInt16(kVK_ANSI_KeypadEnter), []):
            Task { [onSubmit] in
                onSubmit()
            }
        case (UInt16(kVK_Escape), []):
            Task { [onCancel] in
                onCancel()
            }
        default:
            super.keyDown(with: event)
        }
    }
}
