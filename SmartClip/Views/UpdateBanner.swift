import SwiftUI

struct UpdateBanner: View {
    @State private var updateAvailable = false
    @State private var version = ""
    @State private var dismissed = false

    var body: some View {
        if updateAvailable && !dismissed {
            HStack(spacing: 8) {
                Text("v\(version) available")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Button("Later") { dismissed = true }
                    .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.blue.opacity(0.1))
        }
    }
}
