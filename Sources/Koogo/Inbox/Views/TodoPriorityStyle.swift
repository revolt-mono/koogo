import SwiftUI

extension TodoPriority {
    var symbolName: String {
        switch self {
        case .backlog: "circle.dashed"
        case .normal: "circle"
        case .urgent: "exclamationmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .backlog: .secondary
        case .normal: .blue
        case .urgent: .red
        }
    }
}
