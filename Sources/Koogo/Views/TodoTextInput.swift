import AppKit
import SwiftUI

struct TodoTextInput: NSViewRepresentable {
    enum Mode {
        case composing
        case editing(onBlur: () -> Void)

        var onBlur: (() -> Void)? {
            switch self {
            case .composing:
                nil
            case .editing(let onBlur):
                onBlur
            }
        }

        var startsFocused: Bool {
            switch self {
            case .composing:
                false
            case .editing:
                true
            }
        }
    }

    @Binding var text: String
    let mode: Mode
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onBlur: mode.onBlur, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = context.coordinator.textView
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        textView.font =
            font.fontDescriptor.withDesign(.rounded)
            .flatMap { NSFont(descriptor: $0, size: 11) } ?? font
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainerInset = NSSize(width: 5, height: 6)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        context.coordinator.startMonitoringClicks(for: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = context.coordinator.textView
        context.coordinator.onBlur = mode.onBlur
        textView.onSubmit = onSubmit
        if textView.string != text {
            textView.string = text
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        if mode.startsFocused, !context.coordinator.didRequestFocus {
            context.coordinator.didRequestFocus = true
            // Wait for the context menu to close before taking focus.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                scrollView.window?.makeFirstResponder(textView)
            }
        }
    }

    static func dismantleNSView(_: NSScrollView, coordinator: Coordinator) {
        coordinator.onBlur = nil
        coordinator.stopMonitoringClicks()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let text: Binding<String>
        fileprivate let textView: TodoTextView
        var onBlur: (() -> Void)?
        var didRequestFocus = false
        private var clickMonitor: Any?

        init(
            text: Binding<String>,
            onBlur: (() -> Void)?,
            onSubmit: @escaping () -> Void
        ) {
            self.text = text
            self.onBlur = onBlur
            textView = TodoTextView(onSubmit: onSubmit)
        }

        func startMonitoringClicks(for scrollView: NSScrollView) {
            clickMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseUp, .rightMouseUp]
            ) { [weak scrollView, weak textView] event in
                guard let scrollView, let textView, let window = scrollView.window,
                    window.firstResponder === textView
                else {
                    return event
                }
                let isInside =
                    event.window === window
                    && scrollView.bounds.contains(
                        scrollView.convert(event.locationInWindow, from: nil)
                    )
                if !isInside {
                    DispatchQueue.main.async { [weak scrollView, weak textView] in
                        guard let textView, let window = scrollView?.window,
                            window.firstResponder === textView
                        else {
                            return
                        }
                        window.makeFirstResponder(nil)
                    }
                }
                return event
            }
        }

        func stopMonitoringClicks() {
            guard let clickMonitor else {
                return
            }
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            text.wrappedValue = textView.string
        }

        func textDidEndEditing(_: Notification) {
            onBlur?()
        }
    }
}

private final class TodoTextView: NSTextView {
    var onSubmit: () -> Void

    init(onSubmit: @escaping () -> Void) {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer()
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        self.onSubmit = onSubmit
        super.init(frame: .zero, textContainer: textContainer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([
            .shift, .control, .option, .command,
        ])
        guard !hasMarkedText(), event.keyCode == 36 || event.keyCode == 76 else {
            super.keyDown(with: event)
            return
        }

        if modifiers == .shift {
            insertNewlineIgnoringFieldEditor(nil)
            return
        }
        guard modifiers.isEmpty else {
            super.keyDown(with: event)
            return
        }

        // TextKit finishes dispatching this key event after keyDown returns.
        DispatchQueue.main.async { [onSubmit] in
            onSubmit()
        }
    }
}
