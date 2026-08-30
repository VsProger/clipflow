import AppKit

/// Единственный владелец сервисов и единственное место, где они связываются.
///
/// Никакой библиотеки DI: приложение маленькое, а явный композиционный корень
/// читается лучше любого контейнера и делает граф зависимостей очевидным.
@MainActor
final class AppEnvironment {
    let settings: SettingsStore
    let imageStorage: ImageStorage
    let thumbnails: ThumbnailService
    let store: ClipboardStore
    let writeTracker: PasteboardWriteTracker
    let writer: PasteWriter
    let monitor: ClipboardMonitor
    let hotKeyManager: HotKeyManager
    let retention: RetentionService
    let viewModel: ClipboardViewModel

    private(set) var hotKeyErrorMessage: String?
    private var settingsObserver: (any NSObjectProtocol)?

    /// Колбэк для UI: настройки изменились так, что окно стоит перерисовать.
    var onHotKeyErrorChange: (() -> Void)?

    init() throws {
        settings = SettingsStore()
        imageStorage = try ImageStorage()
        thumbnails = ThumbnailService(storage: imageStorage)
        store = try ClipboardStore(
            settings: settings,
            imageStorage: imageStorage,
            thumbnails: thumbnails
        )
        writeTracker = PasteboardWriteTracker()
        writer = PasteWriter(writeTracker: writeTracker, imageStorage: imageStorage)
        monitor = ClipboardMonitor(writeTracker: writeTracker, settings: settings)
        hotKeyManager = HotKeyManager()
        retention = RetentionService(store: store)
        viewModel = ClipboardViewModel(
            store: store,
            settings: settings,
            writer: writer,
            imageStorage: imageStorage
        )
    }

    /// Композиционный корень живёт всё время работы приложения,
    /// поэтому снятие наблюдателя — явная операция, а не deinit
    /// (в nonisolated deinit нельзя трогать не-Sendable свойства).
    func invalidate() {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
            self.settingsObserver = nil
        }
        monitor.invalidate()
        retention.invalidate()
        hotKeyManager.unregister()
    }

    /// Запускает фоновую работу. Вызывается один раз из AppDelegate.
    func start(onHotKeyPress: @escaping () -> Void) {
        hotKeyManager.onPress = onHotKeyPress
        registerHotKey()

        monitor.onCapture = { [weak self] capture in
            guard let self else { return }
            Task { await self.store.insert(capture) }
        }
        monitor.applySettings()

        retention.start()
        applyAppearance()
        observeSettings()
        syncLaunchAtLoginState()
    }

    // MARK: - Settings reactions

    private func observeSettings() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .clipFlowSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let raw = notification.userInfo?["change"] as? String
            MainActor.assumeIsolated {
                self?.handleSettingsChange(raw.flatMap(SettingsChange.init(rawValue:)))
            }
        }
    }

    private func handleSettingsChange(_ change: SettingsChange?) {
        switch change {
        case .hotKey:
            registerHotKey()
        case .monitoring:
            monitor.applySettings()
        case .appearance:
            applyAppearance()
        case .retention, .limit:
            retention.runNow()
        case .launchAtLogin, .none:
            break
        }
    }

    private func registerHotKey() {
        do {
            try hotKeyManager.register(settings.hotKey)
            hotKeyErrorMessage = nil
        } catch {
            hotKeyErrorMessage = (error as? AppError)?.errorDescription
                ?? error.localizedDescription
            Log.hotkey.error("Hot key registration failed")
        }
        onHotKeyErrorChange?()
    }

    private func applyAppearance() {
        NSApp.appearance = settings.appearance.nsAppearance
    }

    /// Приводит состояние тумблера в соответствие реальности: пользователь мог
    /// отключить login item в системных настройках.
    private func syncLaunchAtLoginState() {
        let actual = LaunchAtLogin.isEnabled
        if settings.launchAtLogin != actual {
            settings.launchAtLogin = actual
        }
    }
}
