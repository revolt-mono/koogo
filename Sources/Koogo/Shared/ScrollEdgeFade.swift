import SwiftUI

extension View {
    func scrollEdgeFade(height: CGFloat, trailingInset: CGFloat) -> some View {
        mask {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: height)
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: height)
                }
                Rectangle()
                    .frame(width: trailingInset)
            }
        }
    }
}
