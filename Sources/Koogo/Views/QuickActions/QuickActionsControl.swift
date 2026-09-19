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
        .panelPopover(isPresented: $isPresented) {
            QuickActionsPopoverContent()
        }
    }
}
