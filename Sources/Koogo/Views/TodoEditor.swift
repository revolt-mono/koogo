import AppKit
import SwiftUI

struct TodoEditor: View {
    let onSubmit: (Todo) -> Void

    @State private var draft = TodoDraft()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TodoTextInput(text: $draft.text, onSubmit: submit)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .overlay(alignment: .topLeading) {
                    Text("Add a todo…")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 6)
                        .opacity(draft.text.isEmpty ? 1 : 0)
                        .allowsHitTesting(false)
                }

            HStack(spacing: 8) {
                TodoPrioritySelector(selection: $draft.priority)

                Spacer(minLength: 8)

                Button(action: submit) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .disabled(draft.todoText == nil)
                .accessibilityLabel("Add todo")
            }
        }
        .padding(12)
        .background(
            Color.white.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private func submit() {
        guard let text = draft.todoText else {
            return
        }
        onSubmit(Todo(text: text, priority: draft.priority))
        draft = TodoDraft()
    }
}

private struct TodoDraft {
    var text = ""
    var priority = TodoPriority.normal

    var todoText: TodoText? {
        TodoText(text)
    }
}

private struct TodoTextInput: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
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
        return scrollView
    }

    func updateNSView(_: NSScrollView, context: Context) {
        let textView = context.coordinator.textView
        textView.onSubmit = onSubmit
        if textView.string != text {
            textView.string = text
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let text: Binding<String>
        let textView: TodoTextView

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            textView = TodoTextView(onSubmit: onSubmit)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            text.wrappedValue = textView.string
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
