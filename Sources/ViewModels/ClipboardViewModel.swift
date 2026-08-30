import AppKit

/// Состояние окна истории и все действия над элементами.
///
/// ViewModel не знает про SwiftData и не работает с файлами напрямую —
/// только через `ClipboardStore` и `PasteWriter`.
@Observable
@MainActor
final class ClipboardViewModel {
    let store: ClipboardStore
    let settings: SettingsStore
    let imageStorage: ImageStorage
    private let writer: PasteWriter

    var query = ""
    var selectedID: UUID?
    var previewItem: ClipboardItem?
    var pendingClearConfirmation = false
    var transientMessage: String?

    /// Панель закрывается контроллером — ViewModel только просит об этом.
    var onRequestClose: (() -> Void)?

    private var messageTask: Task<Void, Never>?

    init(
        store: ClipboardStore,
        settings: SettingsStore,
        writer: PasteWriter,
        imageStorage: ImageStorage
    ) {
        self.store = store
        self.settings = settings
        self.writer = writer
        self.imageStorage = imageStorage
    }

    // MARK: - Derived state

    var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// При поиске секции не разделяем: один ранжированный список
    /// позволяет дойти до нужного элемента одной стрелкой.
    var pinnedResults: [ClipboardItem] {
        isSearching ? [] : store.pinnedItems
    }

    var recentResults: [ClipboardItem] {
        isSearching
            ? SearchService.filter(store.items, query: query)
            : store.unpinnedItems
    }

    /// Плоский порядок для навигации с клавиатуры.
    var navigableItems: [ClipboardItem] {
        pinnedResults + recentResults
    }

    var isEmpty: Bool { store.items.isEmpty }
    var hasNoResults: Bool { !isEmpty && navigableItems.isEmpty }

    var selectedItem: ClipboardItem? {
        guard let selectedID else { return nil }
        return navigableItems.first { $0.id == selectedID }
    }

    // MARK: - Lifecycle

    /// Вызывается при каждом показе панели.
    func prepareForPresentation() {
        query = ""
        previewItem = nil
        pendingClearConfirmation = false
        store.reload()
        selectedID = navigableItems.first?.id
    }

    /// Держит выделение валидным после фильтрации или удаления.
    func normalizeSelection() {
        let items = navigableItems
        guard !items.isEmpty else {
            selectedID = nil
            return
        }
        if let selectedID, items.contains(where: { $0.id == selectedID }) { return }
        selectedID = items.first?.id
    }

    // MARK: - Keyboard navigation

    func moveSelection(by offset: Int) {
        let items = navigableItems
        guard !items.isEmpty else { return }
        guard let current = selectedID, let index = items.firstIndex(where: { $0.id == current }) else {
            selectedID = items.first?.id
            return
        }
        let next = min(max(index + offset, 0), items.count - 1)
        selectedID = items[next].id
    }

    func selectFirst() { selectedID = navigableItems.first?.id }
    func selectLast() { selectedID = navigableItems.last?.id }

    // MARK: - Actions

    /// Главный сценарий: элемент уходит в буфер, окно закрывается.
    func activate(_ item: ClipboardItem, variant: PasteWriter.TextVariant = .original) {
        Task {
            let succeeded = await writer.write(item, textVariant: variant)
            guard succeeded else {
                showMessage("Couldn’t read this item — its file is missing.")
                return
            }
            store.markUsed(item)

            if settings.closesAfterSelection {
                onRequestClose?()
                if settings.pastesAutomatically {
                    // Небольшая задержка: фокус должен вернуться прежнему приложению
                    // до того, как мы пошлём ему ⌘V.
                    try? await Task.sleep(for: .milliseconds(80))
                    writer.pasteIntoFrontmostApp()
                }
            } else {
                showMessage("Copied")
            }
        }
    }

    func activateSelection() {
        guard let item = selectedItem else { return }
        activate(item)
    }

    func togglePin(_ item: ClipboardItem) {
        store.togglePin(item)
        normalizeSelection()
    }

    func delete(_ item: ClipboardItem) {
        let items = navigableItems
        let index = items.firstIndex { $0.id == item.id }
        store.delete(item)

        // Выделение переходит на соседа — так серия удалений идёт без мыши.
        let updated = navigableItems
        if let index, !updated.isEmpty {
            selectedID = updated[min(index, updated.count - 1)].id
        } else {
            selectedID = updated.first?.id
        }
    }

    func deleteSelection() {
        guard let item = selectedItem else { return }
        delete(item)
    }

    func showPreview(_ item: ClipboardItem) {
        previewItem = item
    }

    func previewSelection() {
        guard let item = selectedItem else { return }
        previewItem = item
    }

    func requestClearHistory() {
        pendingClearConfirmation = true
    }

    func confirmClearHistory() {
        store.clearHistory(keepingPinned: true)
        pendingClearConfirmation = false
        normalizeSelection()
        showMessage("History cleared")
    }

    func toggleMonitoring() {
        settings.isMonitoringPaused.toggle()
    }

    /// URL полноразмерного файла — нужен ShareLink и Quick Look.
    func imageURL(for item: ClipboardItem) async -> URL? {
        guard let name = item.imageFileName else { return nil }
        return await imageStorage.imageURL(named: name)
    }

    func thumbnailURL(for item: ClipboardItem) async -> URL? {
        guard let name = item.thumbnailFileName else { return nil }
        return await imageStorage.thumbnailURL(named: name)
    }

    /// Варианты «Copy as…», осмысленные для конкретного типа элемента.
    func textVariants(for item: ClipboardItem) -> [PasteWriter.TextVariant] {
        guard let text = item.text else { return [] }
        var variants: [PasteWriter.TextVariant] = []
        if text != text.trimmingCharacters(in: .whitespacesAndNewlines) { variants.append(.trimmed) }
        if text.contains(where: \.isNewline) { variants.append(.singleLine) }
        if item.kind == .link { variants.append(.markdownLink) }
        return variants
    }

    private func showMessage(_ text: String) {
        transientMessage = text
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.transientMessage = nil
        }
    }
}
