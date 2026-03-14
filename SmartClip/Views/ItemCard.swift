import SwiftUI

struct ItemCard: View {
    @EnvironmentObject var viewModel: ClipboardViewModel
    let item: ClipboardItem
    @State private var isHovering = false

    private var isCopied: Bool { viewModel.copiedItemId == item.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: item.contentType == "image" ? "photo" : "doc.text")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
                Text(item.timeAgo).font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()

                if isHovering && !isCopied {
                    HStack(spacing: 2) {
                        Button { viewModel.togglePin(id: item.id!) } label: {
                            Image(systemName: item.pinned ? "pin.fill" : "pin")
                                .font(.system(size: 11))
                                .foregroundStyle(item.pinned ? .secondary : .tertiary)
                        }.buttonStyle(.plain)
                        Button { viewModel.deleteItem(id: item.id!) } label: {
                            Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(.tertiary)
                        }.buttonStyle(.plain)
                    }.transition(.opacity)
                }

                if isCopied {
                    Text("Copied")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .transition(.opacity)
                }
            }

            if item.contentType == "image" {
                if let thumbPath = item.thumbPath, let image = NSImage(contentsOfFile: thumbPath) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.08), lineWidth: 1))
                        .opacity(0.85)
                }
            } else {
                Text(item.preview)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(isCopied ? .white.opacity(0.08) : (isHovering ? .white.opacity(0.06) : .clear)))
        .overlay(alignment: .leading) {
            if item.pinned {
                Rectangle().fill(.white.opacity(0.3)).frame(width: 2).clipShape(RoundedRectangle(cornerRadius: 1))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { viewModel.copyToClipboard(item: item) }
        .onHover { hovering in withAnimation(.easeInOut(duration: 0.12)) { isHovering = hovering } }
    }
}
