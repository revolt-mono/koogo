import SwiftUI

/// text whose digits roll into place when the value changes; the system numeric transition rasterizes each digit into gpu scratch buffers, which adds over 100 MB to the footprint.
struct RollingText: View {
    private static let roll: AnyTransition = .asymmetric(
        insertion: .move(edge: .bottom).combined(with: .opacity),
        removal: .move(edge: .top).combined(with: .opacity)
    )

    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(Array(Self.runs(of: text).enumerated()), id: \.offset) { _, run in
                Text(run)
                    .id(run)
                    .transition(run.first?.isNumber == true ? Self.roll : .opacity)
            }
        }
        .clipped()
        .accessibilityRepresentation { Text(text) }
    }

    /// each digit rolls on its own; other characters keep their kerning as one run.
    private static func runs(of text: String) -> [String] {
        text.reduce(into: []) { runs, character in
            if character.isNumber || runs.last?.first?.isNumber != false {
                runs.append(String(character))
            } else {
                runs[runs.count - 1].append(character)
            }
        }
    }
}
