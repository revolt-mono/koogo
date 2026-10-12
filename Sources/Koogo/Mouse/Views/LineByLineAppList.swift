import AppKit
import SwiftUI

struct LineByLineAppList: View {
    private static let rowHeight: CGFloat = 32

    @Environment(MouseModel.self) private var mouse
    @State private var selection: String?
    @State private var isChoosingApps = false

    var body: some View {
        Text("Each notch scrolls one line in these apps.")
            .foregroundStyle(.secondary)

        List(mouse.settings.lineByLineApps, id: \.self, selection: $selection) { bundleID in
            LineByLineAppRow(bundleID: bundleID)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
        .environment(\.defaultMinListRowHeight, Self.rowHeight)
        .frame(height: Self.rowHeight * CGFloat(mouse.settings.lineByLineApps.count))
        .onDeleteCommand(perform: removeSelection)

        HStack(spacing: 4) {
            Button("Add App", systemImage: "plus") {
                isChoosingApps = true
            }

            Divider()
                .frame(height: 12)

            Button("Remove App", systemImage: "minus", action: removeSelection)
                .disabled(selection == nil)

            Spacer()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .fileImporter(
            isPresented: $isChoosingApps,
            allowedContentTypes: [.application],
            allowsMultipleSelection: true
        ) {
            guard case .success(let apps) = $0 else {
                return
            }
            for bundleID in apps.compactMap({ Bundle(url: $0)?.bundleIdentifier }) {
                mouse.settings.addLineByLineApp(bundleID)
            }
        }
        .fileDialogDefaultDirectory(URL(filePath: "/Applications", directoryHint: .isDirectory))
    }

    private func removeSelection() {
        guard let selection else {
            return
        }
        mouse.settings.removeLineByLineApp(selection)
        self.selection = nil
    }
}

private struct LineByLineAppRow: View {
    let bundleID: String

    var body: some View {
        let location = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)

        HStack(spacing: 8) {
            Image(
                nsImage: location.map { NSWorkspace.shared.icon(forFile: $0.path) }
                    ?? NSWorkspace.shared.icon(for: .application)
            )
            .resizable()
            .frame(width: 24, height: 24)

            Text(location.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID)
        }
    }
}
