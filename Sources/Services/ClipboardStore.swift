import Foundation
import SwiftData

/// Владелец истории: единственный тип, которому разрешено менять базу.
///
/// `@MainActor` осознанно: объём данных мал (десятки-сотни строк метаданных),
/// поэтому вынос ModelContext в отдельный actor дал бы только сложность
/// и гонки при обновлении UI. Всё тяжёлое (файлы, кодирование) уходит
/// в `ImageStorage` / `ThumbnailService`.
@Observable
@MainActor
final class ClipboardStore {
    /// Отсортированный список: закреплённые сверху, дальше по свежести.
    private(set) var items: [ClipboardItem] = []
    private(set) var lastError: AppError?

    private let container: ModelContainer
    private let context: ModelContext
    private let imageStorage: ImageStorage
    private let thumbnails: ThumbnailService
    private let settings: SettingsStore

    init(settings: SettingsStore, imageStorage: ImageStorage, thumbnails: ThumbnailService) throws {
        self.settings = settings
        self.imageStorage = imageStorage
        self.thumbnails = thumbnails

        do {
            let configuration = try ModelConfiguration(url: FileLocations.databaseURL())
            container = try ModelContainer(for: ClipboardItem.self, configurations: configuration)
        } catch {
            Log.store.error("Model container failed: \(error.localizedDescription, privacy: .public)")
            throw AppError.storageUnavailable(underlying: error)
        }

        context = ModelContext(container)
        context.autosaveEnabled = false
        reload()
    }

    // MARK: - Reading

    func reload() {
        let descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        do {
            items = try context.fetch(descriptor).sorted(by: ClipboardItem.isOrderedBefore)
        } catch {
            Log.store.error("Fetch failed: \(error.localizedDescription, privacy: .public)")
            items = []
            lastError = .storageUnavailable(underlying: error)
        }
    }

    var pinnedItems: [ClipboardItem] { items.filter(\.isPinned) }
    var unpinnedItems: [ClipboardItem] { items.filter { !$0.isPinned } }

    // MARK: - Inserting

    func insert(_ capture: ClipboardCapture) async {
        let hash = capture.contentHash

        if let existing = items.first(where: { $0.contentHash == hash }) {
            switch settings.duplicateHandling {
            case .moveToTop:
                existing.updatedAt = capture.capturedAt
                existing.copyCount += 1
                commit()
                sortItems()
                return
            case .keepOldest:
                existing.copyCount += 1
                commit()
                return
            case .allowDuplicates:
                break // проваливаемся в создание нового элемента
            }
        }

        do {
            let item = try await makeItem(from: capture, hash: hash)
            context.insert(item)
            commit()
            items.insert(item, at: 0)
            sortItems()
            enforceLimits()
        } catch let error as AppError {
            lastError = error
            Log.store.error("Insert failed: \(error.localizedDescription, privacy: .public)")
        } catch {
            lastError = .diskWriteFailed(underlying: error)
            Log.store.error("Insert failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func makeItem(from capture: ClipboardCapture, hash: String) async throws -> ClipboardItem {
        switch capture.payload {
        case .text(let text):
            let kind = ContentClassifier.kind(forText: text)
            return ClipboardItem(
                contentHash: hash,
                kind: kind,
                createdAt: capture.capturedAt,
                updatedAt: capture.capturedAt,
                source: capture.source,
                text: text,
                searchIndex: SearchService.makeIndex(for: capture, kind: kind, stored: nil),
                byteSize: capture.byteSize
            )

        case .image(let data, let format):
            let stored = try await imageStorage.store(data: data, format: format)
            let thumbnailName = await thumbnails.makeThumbnail(for: stored)
            return ClipboardItem(
                contentHash: hash,
                kind: .image,
                createdAt: capture.capturedAt,
                updatedAt: capture.capturedAt,
                source: capture.source,
                searchIndex: SearchService.makeIndex(for: capture, kind: .image, stored: stored),
                imageFileName: stored.fileName,
                thumbnailFileName: thumbnailName,
                imageFormat: stored.format,
                pixelWidth: Int(stored.pixelSize.width),
                pixelHeight: Int(stored.pixelSize.height),
                byteSize: stored.byteSize
            )
        }
    }

    // MARK: - Mutating

    func markUsed(_ item: ClipboardItem) {
        item.updatedAt = .now
        item.copyCount += 1
        commit()
        // Порядок в открытом окне намеренно НЕ пересортировываем: список,
        // прыгающий под курсором сразу после выбора, дезориентирует.
        // Новый порядок применится при следующем открытии панели.
    }

    func togglePin(_ item: ClipboardItem) {
        item.isPinned.toggle()
        item.pinnedAt = item.isPinned ? .now : nil
        commit()
        sortItems()
        if item.isPinned { enforcePinnedLimit() } else { enforceLimits() }
    }

    func delete(_ item: ClipboardItem) {
        let image = item.imageFileName
        let thumbnail = item.thumbnailFileName

        items.removeAll { $0.id == item.id }
        context.delete(item)
        commit()

        guard image != nil || thumbnail != nil else { return }
        Task { [imageStorage] in
            await imageStorage.delete(imageNamed: image, thumbnailNamed: thumbnail)
        }
    }

    /// `keepingPinned: true` — поведение по умолчанию для Clear History:
    /// закреплённое пользователь сохранял осознанно.
    func clearHistory(keepingPinned: Bool = true) {
        let doomed = keepingPinned ? unpinnedItems : items
        let files = doomed.map { ($0.imageFileName, $0.thumbnailFileName) }

        for item in doomed { context.delete(item) }
        commit()
        reload()

        Task { [imageStorage] in
            for (image, thumbnail) in files {
                await imageStorage.delete(imageNamed: image, thumbnailNamed: thumbnail)
            }
        }
        Log.store.info("Cleared \(doomed.count, privacy: .public) items")
    }

    // MARK: - Retention

    /// Лимит применяется только к незакреплённым: 30 обычных + закреплённые отдельно.
    func enforceLimits() {
        let unpinned = unpinnedItems
        guard unpinned.count > settings.historyLimit else { return }
        for item in unpinned.dropFirst(settings.historyLimit) {
            delete(item)
        }
    }

    private func enforcePinnedLimit() {
        let pinned = pinnedItems
        guard pinned.count > settings.pinnedLimit else { return }
        // Самые старые закреплённые открепляются, а не удаляются:
        // молча терять то, что пользователь пометил как важное, недопустимо.
        for item in pinned.dropFirst(settings.pinnedLimit) {
            item.isPinned = false
            item.pinnedAt = nil
        }
        commit()
        sortItems()
        enforceLimits()
    }

    func purgeExpired() {
        guard let interval = settings.retentionPeriod.timeInterval else { return }
        let cutoff = Date.now.addingTimeInterval(-interval)
        let expired = items.filter { !$0.isPinned && $0.updatedAt < cutoff }
        guard !expired.isEmpty else { return }
        for item in expired { delete(item) }
        Log.store.info("Purged \(expired.count, privacy: .public) expired items")
    }

    /// Подчистка файлов, потерявших владельца (например, после краша).
    func removeOrphanFiles() async {
        let images = Set(items.compactMap(\.imageFileName))
        let thumbnails = Set(items.compactMap(\.thumbnailFileName))
        await imageStorage.removeOrphans(keepingImages: images, thumbnails: thumbnails)
    }

    func storageSizeOnDisk() async -> Int {
        await imageStorage.totalBytesOnDisk()
    }

    // MARK: - Private

    private func sortItems() {
        items.sort(by: ClipboardItem.isOrderedBefore)
    }

    private func commit() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            Log.store.error("Save failed: \(error.localizedDescription, privacy: .public)")
            lastError = .diskWriteFailed(underlying: error)
            context.rollback()
            reload()
        }
    }
}
