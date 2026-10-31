import AppKit
import Carbon.HIToolbox
import SwiftUI

struct TodoTextInput: NSViewRepresentable {
    static let maxHeight: CGFloat = 56

    enum Mode {
        case composing
        case editing

        var font: NSFont {
            switch self {
            case .composing:
                let base = NSFont.systemFont(ofSize: 11, weight: .medium)
                return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: base.pointSize) }
                    ?? base
            case .editing:
                return NSFont.systemFont(ofSize: 10, weight: .medium)
            }
        }

        /// editing insets keep a single line at the 18pt row icon height so the row does not move.
        var textInset: NSSize {
            switch self {
            case .composing: NSSize(width: 5, height: 6)
            case .editing: NSSize(width: 5, height: 3)
            }
        }
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
        textView.font = mode.font
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainerInset = mode.textInset
        textView.textContainer?.lineFragmentPadding = 0

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        if case .editing = mode {
            // take focus after the native context menu closes.
            Task {
                try? await Task.sleep(for: .milliseconds(50))
                scrollView.window?.makeFirstResponder(textView)
            }
        }
        return scrollView
    }

    func updateNSView(_: NSScrollView, context: Context) {
        let textView = context.coordinator.textView
        context.coordinator.text = $text
        textView.onSubmit = onSubmit
        textView.onCancel = onCancel
        if textView.string != text {
            textView.string = text
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
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
        container.size.width = width - mode.textInset.width * 2
        layoutManager.ensureLayout(for: container)
        let lineHeight = layoutManager.defaultLineHeight(for: mode.font)
        let textHeight = max(layoutManager.usedRect(for: container).height, lineHeight)
        return CGSize(width: width, height: min(textHeight + mode.textInset.height * 2, Self.maxHeight))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        fileprivate let textView = TodoTextView(usingTextLayoutManager: false)

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

        // textkit finishes key dispatch after the key handler returns; defer callbacks one run-loop turn.
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
