import SwiftUI

/// Кеш превью с ограничением по стоимости: NSCache сама вытесняет
/// изображения при нехватке памяти, поэтому список не превращается
/// в удерживаемый мегабайтный буфер.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 24 * 1_024 * 1_024 // ~24 МБ
        return cache
    }()

    private init() {}

    func cachedImage(for key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    func store(_ image: NSImage, for key: String, cost: Int) {
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}

/// Превью изображения в ряду списка. Загружается лениво и вне main thread;
/// пока файл читается, показывается заглушка — список не «дёргается».
struct ThumbnailImageView: View {
    let item: ClipboardItem
    let storage: ImageStorage
    var size: CGFloat = 40

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                            .font(.system(size: size * 0.34))
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
        .task(id: item.thumbnailFileName) { await load() }
    }

    private func load() async {
        guard let name = item.thumbnailFileName ?? item.imageFileName else { return }
        if let cached = ThumbnailCache.shared.cachedImage(for: name) {
            image = cached
            return
        }

        let data: Data? = item.thumbnailFileName != nil
            ? await storage.data(forThumbnailNamed: name)
            : await storage.data(forImageNamed: name)

        guard let data, let loaded = NSImage(data: data) else { return }
        ThumbnailCache.shared.store(loaded, for: name, cost: data.count)
        image = loaded
    }
}
