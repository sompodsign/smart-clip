import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: ClipboardViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SmartClip")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                SettingsMenu()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(viewModel.itemCount)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(viewModel.isPro ? " items" : " / 5")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()
            SearchBar()
            Divider()
            ClipList()
            Divider()
            LicenseGate()
        }
        .frame(width: 340)
        .background(.ultraThinMaterial)
    }
}
