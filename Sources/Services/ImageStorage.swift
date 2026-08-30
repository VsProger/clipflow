import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Хранилище изображений на диске.
///
/// Actor, потому что кодирование/декодирование и файловый I/O не должны
/// блокировать main thread: скриншот 6K в TIFF — это десятки мегабайт.
/// В RAM ничего не кешируется: список рисуется по thumbnails,
/// полноразмерное изображение читается только для preview или вставки.
actor ImageStorage {
    /// Изображения крупнее лимита перекодируются с понижением разрешения:
    /// история буфера не должна становиться архивом.
    private let maximumStoredPixels = 12_000_000 // ~12 Мп
    private let imagesDirectory: URL
    private let thumbnailsDirectory: URL

    init() throws {
        do {
            imagesDirectory = try FileLocations.imagesDirectory()
            thumbnailsDirectory = try FileLocations.thumbnailsDirectory()
        } catch {
            throw AppError.diskWriteFailed(underlying: error)
        }
    }

    // MARK: - Writing

    func store(data: Data, format: ImageFormat) throws -> StoredImage {
        guard let properties = ImageInspector.inspect(data) else {
            throw AppError.imageDecodingFailed
        }

        let normalized = try normalize(data: data, format: format, properties: properties)
        try ensureSpace(for: normalized.data.count)

        let fileName = "\(UUID().uuidString).\(normalized.format.fileExtension)"
        let url = imagesDirectory.appendingPathComponent(fileName)
        do {
            try normalized.data.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            throw AppError.diskWriteFailed(underlying: error)
        }

        return StoredImage(
            fileName: fileName,
            format: normalized.format,
            byteSize: normalized.data.count,
            pixelSize: normalized.pixelSize
        )
    }

    func storeThumbnail(data: Data, forImageNamed imageName: String) throws -> String {
        let fileName = "thumb-\(imageName).png"
        let url = thumbnailsDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw AppError.diskWriteFailed(underlying: error)
        }
        return fileName
    }

    // MARK: - Reading

    func imageURL(named name: String) -> URL {
        imagesDirectory.appendingPathComponent(name)
    }

    func thumbnailURL(named name: String) -> URL {
        thumbnailsDirectory.appendingPathComponent(name)
    }

    func data(forImageNamed name: String) -> Data? {
        try? Data(contentsOf: imageURL(named: name), options: .mappedIfSafe)
    }

    func data(forThumbnailNamed name: String) -> Data? {
        try? Data(contentsOf: thumbnailURL(named: name), options: .mappedIfSafe)
    }

    // MARK: - Deleting

    func delete(imageNamed image: String?, thumbnailNamed thumbnail: String?) {
        let fm = FileManager.default
        if let image { try? fm.removeItem(at: imageURL(named: image)) }
        if let thumbnail { try? fm.removeItem(at: thumbnailURL(named: thumbnail)) }
    }

    /// Удаляет файлы, на которые больше не ссылается ни один элемент истории.
    /// Вызывается при запуске: страховка от аварийного завершения приложения
    /// между записью файла и коммитом транзакции.
    func removeOrphans(keepingImages images: Set<String>, thumbnails: Set<String>) {
        let fm = FileManager.default
        var reclaimed = 0

        for (directory, keep) in [(imagesDirectory, images), (thumbnailsDirectory, thumbnails)] {
            guard let contents = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in contents where !keep.contains(url.lastPathComponent) {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if (try? fm.removeItem(at: url)) != nil { reclaimed += size }
            }
        }

        if reclaimed > 0 {
            Log.storage.info("Reclaimed \(reclaimed, privacy: .public) bytes of orphaned files")
        }
    }

    func totalBytesOnDisk() -> Int {
        let fm = FileManager.default
        return [imagesDirectory, thumbnailsDirectory].reduce(into: 0) { total, directory in
            guard let contents = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { return }
            for url in contents {
                total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            }
        }
    }

    // MARK: - Private

    private struct NormalizedImage {
        let data: Data
        let format: ImageFormat
        let pixelSize: CGSize
    }

    /// TIFF и неизвестные форматы перекодируются в PNG (без потерь, кратно меньше).
    /// Уже компактные форматы сохраняются байт-в-байт, чтобы не терять качество
    /// и не тратить CPU.
    private func normalize(
        data: Data,
        format: ImageFormat,
        properties: ImageProperties
    ) throws -> NormalizedImage {
        let needsDownscale = properties.pixelWidth * properties.pixelHeight > maximumStoredPixels
        let needsRecoding = format == .tiff || format == .unknown || format == .bmp

        guard needsDownscale || needsRecoding else {
            return NormalizedImage(data: data, format: format, pixelSize: properties.pixelSize)
        }

        let maxDimension = needsDownscale ? 4_096 : max(properties.pixelWidth, properties.pixelHeight)
        guard let encoded = ImageInspector.recode(
            data,
            to: .png,
            maxPixelSize: maxDimension
        ) else {
            // Перекодировать не удалось — сохраняем оригинал, лучше чем потерять элемент.
            Log.storage.warning("Falling back to original bytes: re-encoding failed")
            return NormalizedImage(data: data, format: format, pixelSize: properties.pixelSize)
        }
        return NormalizedImage(data: encoded.data, format: .png, pixelSize: encoded.pixelSize)
    }

    private func ensureSpace(for bytes: Int) throws {
        // Требуем двойной запас: файл плюс thumbnail плюс место под БД.
        let required = bytes * 2 + 1_048_576
        guard let available = FileLocations.availableCapacity() else { return }
        guard available > required else {
            throw AppError.insufficientDiskSpace(required: required)
        }
    }
}
