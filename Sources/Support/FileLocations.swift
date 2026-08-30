import CryptoKit
import Foundation

/// Единая точка правды о том, где живут данные приложения.
///
/// ~/Library/Application Support/ClipFlow/
///   ├── ClipFlow.store        (SwiftData: только метаданные)
///   ├── Images/               (полноразмерные изображения)
///   └── Thumbnails/           (превью, ≤ 320 px по большей стороне)
enum FileLocations {
    static let directoryName = "ClipFlow"

    static func root() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base.appendingPathComponent(directoryName, isDirectory: true)
        try ensureDirectory(at: root)
        return root
    }

    static func imagesDirectory() throws -> URL {
        let url = try root().appendingPathComponent("Images", isDirectory: true)
        try ensureDirectory(at: url)
        return url
    }

    static func thumbnailsDirectory() throws -> URL {
        let url = try root().appendingPathComponent("Thumbnails", isDirectory: true)
        try ensureDirectory(at: url)
        return url
    }

    static func databaseURL() throws -> URL {
        try root().appendingPathComponent("ClipFlow.store")
    }

    /// Создаёт каталог с правами 0700 и исключает его из резервных копий:
    /// содержимое буфера обмена не должно уезжать в iCloud/Time Machine.
    private static func ensureDirectory(at url: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        var mutable = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutable.setResourceValues(values)
    }

    /// Свободное место на томе, где лежит хранилище.
    static func availableCapacity() -> Int? {
        guard let root = try? root(),
              let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let capacity = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return Int(clamping: capacity)
    }
}

enum ContentHash {
    /// SHA-256 используется только для дедупликации — не для безопасности.
    /// Хешируем байты как есть, чтобы не изменять и не нормализовать контент пользователя.
    static func of(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func of(_ string: String) -> String {
        of(Data(string.utf8))
    }
}
