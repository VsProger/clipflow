import Foundation
import SwiftData

/// Элемент истории. В базе лежат ТОЛЬКО метаданные: сами изображения
/// и thumbnails — файлы на диске, здесь хранятся их имена.
///
/// `createdAt` — когда содержимое встретилось впервые.
/// `updatedAt` — когда его скопировали/использовали последний раз; по нему сортируется список.
@Model
final class ClipboardItem {
    @Attribute(.unique) var id: UUID

    /// Не помечен `.unique` намеренно: в режиме `allowDuplicates` два элемента
    /// могут иметь одинаковый хеш, а unique-атрибут превратил бы вставку в upsert.
    var contentHash: String

    var kindRaw: String
    var createdAt: Date
    var updatedAt: Date
    var copyCount: Int

    var isPinned: Bool
    var pinnedAt: Date?

    var sourceBundleID: String?
    var sourceAppName: String?

    // MARK: Text payload
    var text: String?

    /// Предвычисленная нормализованная строка для мгновенного поиска.
    var searchIndex: String

    // MARK: Image payload
    var imageFileName: String?
    var thumbnailFileName: String?
    var imageFormatRaw: String?
    var pixelWidth: Int
    var pixelHeight: Int

    /// Размер payload в байтах: длина UTF-8 для текста, размер файла для изображения.
    var byteSize: Int

    init(
        id: UUID = UUID(),
        contentHash: String,
        kind: ItemKind,
        createdAt: Date,
        updatedAt: Date,
        copyCount: Int = 1,
        isPinned: Bool = false,
        pinnedAt: Date? = nil,
        source: SourceApp? = nil,
        text: String? = nil,
        searchIndex: String,
        imageFileName: String? = nil,
        thumbnailFileName: String? = nil,
        imageFormat: ImageFormat? = nil,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0,
        byteSize: Int
    ) {
        self.id = id
        self.contentHash = contentHash
        self.kindRaw = kind.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.copyCount = copyCount
        self.isPinned = isPinned
        self.pinnedAt = pinnedAt
        self.sourceBundleID = source?.bundleID
        self.sourceAppName = source?.name
        self.text = text
        self.searchIndex = searchIndex
        self.imageFileName = imageFileName
        self.thumbnailFileName = thumbnailFileName
        self.imageFormatRaw = imageFormat?.rawValue
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.byteSize = byteSize
    }
}

// MARK: - Derived, UI-facing properties

extension ClipboardItem {
    var kind: ItemKind {
        ItemKind(rawValue: kindRaw) ?? .text
    }

    var imageFormat: ImageFormat {
        imageFormatRaw.flatMap(ImageFormat.init(rawValue:)) ?? .unknown
    }

    var isImage: Bool { kind.isImage }

    /// Первая значимая строка — заголовок ряда.
    var titleLine: String {
        guard let text else { return "\(imageFormat.displayName) \(dimensionsLabel)" }
        let firstLine = text
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? text
        let collapsed = firstLine.trimmingCharacters(in: .whitespaces)
        return collapsed.isEmpty ? text.trimmingCharacters(in: .whitespacesAndNewlines) : collapsed
    }

    /// До трёх строк превью, без изменения исходного содержимого.
    var previewSnippet: String? {
        guard let text, text.contains("\n") else { return nil }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().prefix(2)
        let snippet = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return snippet.isEmpty ? nil : snippet
    }

    var lineCount: Int {
        guard let text else { return 0 }
        return text.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    var dimensionsLabel: String {
        pixelWidth > 0 && pixelHeight > 0 ? "\(pixelWidth)×\(pixelHeight)" : ""
    }

    var byteSizeLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteSize), countStyle: .file)
    }

    /// Ключ сортировки: закреплённые всегда сверху, внутри секции — по свежести.
    static func isOrderedBefore(_ lhs: ClipboardItem, _ rhs: ClipboardItem) -> Bool {
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
        if lhs.isPinned, rhs.isPinned {
            let l = lhs.pinnedAt ?? lhs.updatedAt
            let r = rhs.pinnedAt ?? rhs.updatedAt
            if l != r { return l > r }
        }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.id.uuidString > rhs.id.uuidString
    }
}
