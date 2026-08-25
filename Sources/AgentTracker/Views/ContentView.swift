import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Agent Tracker")
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text("Track agent work from one place.")
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(minWidth: 480, minHeight: 320)
    }
}
