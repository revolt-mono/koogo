import SwiftUI

struct QuickActionsControl: View {
    var body: some View {
        PanelDisclosure { isPresented in
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
            .background(
                isPresented ? Color.panelRaised : .clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
        } content: {
            QuickActionsPopoverContent()
        }
    }
}
