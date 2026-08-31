import AppKit
import Foundation
import SwiftUI

struct InboxView: View {
    private static let defaultsKey = "inbox-todo-items"

    private let dismissInput: () -> Void

    @State private var draft = ""
    @State private var todos: [Todo]

    init(dismissInput: @escaping () -> Void) {
        self.dismissInput = dismissInput
        _todos = State(initialValue: Self.loadTodos())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("Add a todo…")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 6)
                            .allowsHitTesting(false)
                    }

                    TodoInput(
                        text: $draft,
                        onSubmit: addTodo
                    )
                }
                .frame(height: 56)

                Button {
                    addTodo(draft)
                    dismissInput()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .disabled(Todo.normalizedText(from: draft) == nil)
                .accessibilityLabel("Add todo")
            }
            .padding(12)
            .background(
                Color.white.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(todos) { todo in
                        TodoRow(todo: todo) {
                            if let index = todos.firstIndex(where: { $0.id == todo.id }) {
                                todos[index].isCompleted.toggle()
                            }
                        }
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                todos.removeAll { $0.id == todo.id }
                                dismissInput()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.automatic)
            .contentShape(.rect)
            .simultaneousGesture(
                TapGesture().onEnded {
                    dismissInput()
                }
            )
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 32)
        .frame(maxHeight: .infinity, alignment: .top)
        .onChange(of: todos, persistTodos)
    }

    private func addTodo(_ input: String) {
        guard let todo = Todo(input) else {
            return
        }
        todos.insert(todo, at: 0)
        draft = ""
    }

    private func persistTodos() {
        guard let data = try? PropertyListEncoder().encode(todos) else {
            return
        }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private static func loadTodos() -> [Todo] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
            let todos = try? PropertyListDecoder().decode([Todo].self, from: data)
        else {
            return []
        }
        return todos
    }
}

private struct TodoInput: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = TodoTextView()
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        textView.font =
            font.fontDescriptor.withDesign(.rounded)
            .flatMap { NSFont(descriptor: $0, size: 11) } ?? font
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isHorizontallyResizable = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 5, height: 6)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? TodoTextView else {
            return
        }
        textView.onSubmit = onSubmit
        if textView.string != text {
            textView.string = text
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
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
    var onSubmit: (String) -> Void = { _ in }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([
            .shift, .control, .option, .command,
        ])
        guard !hasMarkedText(), event.keyCode == 36 || event.keyCode == 76 else {
            super.keyDown(with: event)
            return
        }

        if modifiers == .shift {
            insertText("\n", replacementRange: selectedRange())
        } else if modifiers.isEmpty {
            let text = string
            let onSubmit = onSubmit
            // TextKit finishes dispatching this key event after keyDown returns.
            DispatchQueue.main.async {
                onSubmit(text)
            }
        } else {
            super.keyDown(with: event)
        }
    }
}

private struct Todo: Codable, Equatable, Identifiable {
    let id: UUID
    let text: String
    var isCompleted: Bool

    init?(_ input: String) {
        guard let text = Self.normalizedText(from: input) else {
            return nil
        }
        id = UUID()
        self.text = text
        isCompleted = false
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard
            let text = Self.normalizedText(
                from: try values.decode(String.self, forKey: .text)
            )
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .text,
                in: values,
                debugDescription: "Todo text must not be empty"
            )
        }
        id = try values.decode(UUID.self, forKey: .id)
        self.text = text
        isCompleted = try values.decode(Bool.self, forKey: .isCompleted)
    }

    static func normalizedText(from input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

private struct TodoRow: View {
    let todo: Todo
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 18, height: 18)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(todo.isCompleted ? Color.accentColor : Color.secondary)
            .accessibilityLabel(todo.isCompleted ? "Mark incomplete" : "Mark complete")

            Text(todo.text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                .strikethrough(todo.isCompleted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(
            Color.white.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }
}
