import SwiftUI

struct ClipList: View {
    @EnvironmentObject var viewModel: ClipboardViewModel

    var body: some View {
        if viewModel.items.isEmpty {
            VStack(spacing: 6) {
                Text("📋").font(.system(size: 28)).opacity(0.4)
                Text("No clips yet").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Text("Copy something to get started").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(viewModel.items) { item in
                        ItemCard(item: item)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
        }
    }
}
