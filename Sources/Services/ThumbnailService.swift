import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ImageProperties: Sendable {
    let pixelWidth: Int
    let pixelHeight: Int

    var pixelSize: CGSize { CGSize(width: pixelWidth, height: pixelHeight) }
}

/// Работа с изображениями через ImageIO.
///
/// Ключевой момент производительности: размеры читаются из метаданных без
/// декодирования, а thumbnails строятся через
/// `CGImageSourceCreateThumbnailAtMaxPixelSize` — Core Graphics декодирует
/// напрямую в целевой размер и никогда не держит полный битмап в памяти.
enum ImageInspector {
    static func inspect(_ data: Data) -> ImageProperties? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return nil }
        return ImageProperties(pixelWidth: width, pixelHeight: height)
    }

    struct Encoded {
        let data: Data
        let pixelSize: CGSize
    }

    static func recode(_ data: Data, to format: ImageFormat, maxPixelSize: Int) -> Encoded? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        guard let encoded = encode(image, as: format) else { return nil }
        return Encoded(
            data: encoded,
            pixelSize: CGSize(width: image.width, height: image.height)
        )
    }

    static func encode(_ image: CGImage, as format: ImageFormat) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData,
            format.utType.identifier as CFString,
            1,
            nil
        ) else { return nil }

        var properties: [CFString: Any] = [:]
        if format == .jpeg { properties[kCGImageDestinationLossyCompressionQuality] = 0.82 }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

/// Генерация превью для списка.
actor ThumbnailService {
    /// 320 px хватает для ряда высотой ~56 pt даже на Retina-дисплеях.
    static let maxPixelSize = 320

    private let storage: ImageStorage

    init(storage: ImageStorage) {
        self.storage = storage
    }

    /// Возвращает имя файла thumbnail. Ошибка генерации не критична:
    /// элемент останется в истории, в списке будет иконка-заглушка.
    func makeThumbnail(for stored: StoredImage) async -> String? {
        guard let data = await storage.data(forImageNamed: stored.fileName) else { return nil }
        guard let encoded = ImageInspector.recode(
            data,
            to: .png,
            maxPixelSize: Self.maxPixelSize
        ) else {
            Log.storage.warning("Thumbnail generation failed for stored image")
            return nil
        }
        do {
            return try await storage.storeThumbnail(data: encoded.data, forImageNamed: stored.fileName)
        } catch {
            Log.storage.warning("Thumbnail write failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
