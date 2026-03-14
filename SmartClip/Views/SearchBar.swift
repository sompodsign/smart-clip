import SwiftUI

struct SearchBar: View {
    @EnvironmentObject var viewModel: ClipboardViewModel
    @State private var localQuery: String = ""
    @State private var debounceTask: Task<Void, Never>?

    private let filters = [("all", "All"), ("text", "Text"), ("image", "Images")]

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                TextField("Search clipboard history...", text: $localQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onChange(of: localQuery) { _, newValue in debounceSearch(newValue) }
                if !localQuery.isEmpty {
                    Button { localQuery = ""; viewModel.updateSearch("") } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(.tertiary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 4) {
                ForEach(filters, id: \.0) { value, label in
                    Button { viewModel.setFilter(value) } label: {
                        Text(label)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(viewModel.activeFilter == value ? AnyShapeStyle(.white.opacity(0.12)) : AnyShapeStyle(.clear))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(viewModel.activeFilter == value ? .primary : .tertiary)
                    }.buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func debounceSearch(_ query: String) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            viewModel.updateSearch(query)
        }
    }
}
