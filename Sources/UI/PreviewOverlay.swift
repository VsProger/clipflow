import SwiftUI

/// Увеличенный preview поверх списка.
/// Не отдельное окно — иначе панель потеряет key-статус и клавиатура «отвалится».
struct PreviewOverlay: View {
    let item: ClipboardItem
    let viewModel: ClipboardViewModel

    @State private var fullImage: NSImage?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.28))
                .onTapGesture { viewModel.previewItem = nil }

            VStack(spacing: 0) {
                header

                Divider().opacity(0.5)

                ScrollView {
                    contentBody
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider().opacity(0.5)

                HStack(spacing: 8) {
                    Text(item.createdAt, format: .dateTime.month().day().hour().minute())
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    if let app = item.sourceAppName {
                        Text("· from \(app)")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button("Copy") { viewModel.activate(item) }
                        .controlSize(.small)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 0.5)
            }
            .shadow(radius: 20, y: 6)
            .padding(16)
        }
        .task(id: item.id) { await loadFullImageIfNeeded() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: item.kind.symbolName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Text(item.isImage ? "\(item.imageFormat.displayName) · \(item.dimensionsLabel) · \(item.byteSizeLabel)" : item.kind.displayName)
                .font(.system(size: 11, weight: .semibold))

            Spacer()

            Button {
                viewModel.previewItem = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close preview (⎋)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var contentBody: some View {
        if item.isImage {
            if let fullImage {
                Image(nsImage: fullImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        } else if let text = item.text {
            // Текст выделяемый: preview заодно служит для копирования фрагмента.
            Text(text)
                .textSelection(.enabled)
                .font(item.kind == .code
                      ? .system(size: 11.5, design: .monospaced)
                      : .system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func loadFullImageIfNeeded() async {
        guard item.isImage, let name = item.imageFileName else { return }
        // Полноразмерное изображение читается только здесь и не кешируется:
        // в RAM оно живёт лишь пока открыт preview.
        guard let data = await viewModel.imageStorage.data(forImageNamed: name) else { return }
        fullImage = NSImage(data: data)
    }
}
