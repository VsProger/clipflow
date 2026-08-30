import SwiftUI

struct ItemRowView: View {
    let item: ClipboardItem
    let viewModel: ClipboardViewModel
    let isSelected: Bool

    @Environment(SettingsStore.self) private var settings
    @State private var isHovering = false
    @State private var shareURL: URL?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            leadingVisual

            VStack(alignment: .leading, spacing: 2) {
                Text(item.titleLine)
                    .font(item.kind == .code ? .system(size: 12, design: .monospaced) : .system(size: 12))
                    .lineLimit(item.isImage ? 1 : 2)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)

                if let snippet = item.previewSnippet, !item.isImage {
                    Text(snippet)
                        .font(item.kind == .code ? .system(size: 10.5, design: .monospaced) : .system(size: 10.5))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }

                metadataLine
            }

            Spacer(minLength: 4)

            if isHovering {
                hoverActions
                    .transition(.opacity)
            } else if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                    .rotationEffect(.degrees(45))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(background)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering in
            isHovering = hovering
            if hovering { viewModel.selectedID = item.id }
        }
        .onTapGesture(count: 2) { viewModel.activate(item) }
        .onTapGesture {
            viewModel.selectedID = item.id
            if settings.copiesOnSingleClick { viewModel.activate(item) }
        }
        .contextMenu { contextMenu }
        .animation(.easeOut(duration: 0.1), value: isHovering)
        .task(id: item.id) {
            // URL полноразмерного файла нужен только для ShareLink; читаем лениво.
            guard item.isImage else { return }
            shareURL = await viewModel.imageURL(for: item)
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var leadingVisual: some View {
        if item.isImage {
            ThumbnailImageView(item: item, storage: viewModel.imageStorage)
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary.opacity(0.6))
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: item.kind.symbolName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var metadataLine: some View {
        HStack(spacing: 5) {
            Text(item.kind.displayName)
                .foregroundStyle(.tertiary)

            Text("·").foregroundStyle(.quaternary)

            Text(item.updatedAt, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                .foregroundStyle(.tertiary)

            if item.isImage {
                Text("·").foregroundStyle(.quaternary)
                Text("\(item.dimensionsLabel) · \(item.byteSizeLabel)")
                    .foregroundStyle(.tertiary)
            } else if item.lineCount > 1 {
                Text("·").foregroundStyle(.quaternary)
                Text("\(item.lineCount) lines")
                    .foregroundStyle(.tertiary)
            }

            if item.copyCount > 1 {
                Text("×\(item.copyCount)")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 3)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
        }
        .font(.system(size: 10))
        .lineLimit(1)
    }

    private var hoverActions: some View {
        HStack(spacing: 2) {
            iconButton(item.isPinned ? "pin.slash" : "pin", help: item.isPinned ? "Unpin" : "Pin (⌘P)") {
                viewModel.togglePin(item)
            }
            iconButton("eye", help: "Preview (⌘Y)") {
                viewModel.showPreview(item)
            }
            iconButton("trash", help: "Delete (⌘⌫)") {
                viewModel.delete(item)
            }
        }
    }

    private func iconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Copy") { viewModel.activate(item) }

        ForEach(viewModel.textVariants(for: item)) { variant in
            Button(variant.title) { viewModel.activate(item, variant: variant) }
        }

        if item.isImage {
            Button("Copy as PNG") { viewModel.activate(item) }
        }

        Divider()

        Button(item.isPinned ? "Unpin" : "Pin") { viewModel.togglePin(item) }
        Button("Quick Look") { viewModel.showPreview(item) }

        if let text = item.text {
            ShareLink(item: text) { Text("Share…") }
        } else if let url = shareURL {
            ShareLink(item: url) { Text("Share…") }
        }

        Divider()

        Button("Delete", role: .destructive) { viewModel.delete(item) }
    }

    private var background: AnyShapeStyle {
        if isSelected {
            AnyShapeStyle(Color.accentColor.opacity(0.18))
        } else if isHovering {
            AnyShapeStyle(.quaternary.opacity(0.35))
        } else {
            AnyShapeStyle(.clear)
        }
    }
}
