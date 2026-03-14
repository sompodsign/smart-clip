import SwiftUI

struct SettingsMenu: View {
    @EnvironmentObject var viewModel: ClipboardViewModel
    private let itemLimits: [Int64] = [20, 50, 100, 200]

    var body: some View {
        Menu {
            Section("Max Items") {
                ForEach(itemLimits, id: \.self) { limit in
                    Button {
                        viewModel.updateMaxItems(limit)
                    } label: {
                        HStack {
                            Text("\(limit)")
                            if viewModel.maxItems == limit { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
            Divider()
            Button {
                viewModel.togglePlainTextOnly()
            } label: {
                HStack {
                    Text("Plain Text Only")
                    if viewModel.plainTextOnly { Image(systemName: "checkmark") }
                }
            }
            Divider()
            Button("Quit SmartClip") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        } label: {
            Image(systemName: "gearshape").font(.system(size: 14)).foregroundStyle(.tertiary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
