import SwiftUI

struct TodoList: View {
  var body: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(inboxModel.todos) { todo in
          if todo.id != inboxModel.todos.first?.id {
            DashedLine()
              .stroke(.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
              .frame(height: 1)
          }
          TodoRow(todo: todo, editingID: $editingID)
        }
      }
      .frame(maxWidth: .infinity, alignment: .top)
    }
    .panelPageScroll()
  }

  @Environment(InboxModel.self) private var inboxModel
  @State private var editingID: Todo.ID?
}

private struct DashedLine: Shape {
  func path(in rect: CGRect) -> Path {
    Path { path in
      path.move(to: CGPoint(x: rect.minX, y: rect.midY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
    }
  }
}

private struct TodoRow: View {
  let todo: Todo

  @Binding var editingID: Todo.ID?

  var body: some View {
    let isEditing = editingID == todo.id
    HStack(spacing: 8) {
      Button {
        inboxModel.toggleCompleted(todo.id)
      } label: {
        Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 12, weight: .medium))
          .frame(width: 18, height: 18)
          .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .foregroundStyle(todo.isCompleted ? Color.accentColor : Color.secondary)
      .accessibilityLabel(todo.isCompleted ? "Mark incomplete" : "Mark complete")

      Image(systemName: todo.priority.symbolName)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(todo.priority.color)
        .frame(width: 14, height: 18)
        .accessibilityLabel("\(todo.priority.title) priority")

      if isEditing {
        TodoInlineEditor(text: todo.text, onFinish: finishEditing)
      } else {
        Text(todo.text.value)
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(todo.isCompleted ? .secondary : .primary)
          .strikethrough(todo.isCompleted)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(.rect)
          .onTapGesture(count: 2) {
            editingID = todo.id
          }
      }
    }
    .padding(8)
    .background(
      Color.accentColor.opacity(isEditing ? 0.16 : 0),
      in: .rect(cornerRadius: 7),
    )
    .padding(.vertical, 2)
    .padding(.horizontal, -8)
    .contextMenu {
      Button("Edit") {
        editingID = todo.id
      }

      Picker(
        "Priority",
        selection: Binding(
          get: { todo.priority },
          set: { inboxModel.setPriority($0, of: todo.id) },
        ),
      ) {
        ForEach(TodoPriority.allCases, id: \.self) { priority in
          Text(priority.title)
            .tag(priority)
        }
      }
      .pickerStyle(.menu)

      Button("Delete", role: .destructive) {
        inboxModel.delete(todo.id)
      }
    }
  }

  @Environment(InboxModel.self) private var inboxModel

  private func finishEditing(_ text: TodoText?) {
    if let text {
      inboxModel.setText(text, of: todo.id)
    }
    editingID = nil
  }
}

private struct TodoInlineEditor: View {
  init(text: TodoText, onFinish: @escaping (TodoText?) -> Void) {
    self.onFinish = onFinish
    _draft = State(initialValue: text.value)
  }

  /// receives nil when the edit is discarded.
  let onFinish: (TodoText?) -> Void

  var body: some View {
    TodoTextInput(
      text: $draft,
      mode: .editing,
      onSubmit: submit,
      onCancel: { onFinish(nil) },
    )
    .frame(maxWidth: .infinity)
    // the field grows into the icon gap so the text itself stays where the label was.
    .padding(.horizontal, -TodoTextInput.Mode.editing.textInset.width)
    // textkit places the baseline half a point below where swiftui draws the same label.
    .offset(y: -0.5)
    .onMouseDownOutside { _ in onFinish(nil) }
  }

  @State private var draft: String

  private func submit() {
    if let text = TodoText(draft) {
      onFinish(text)
    }
  }
}
