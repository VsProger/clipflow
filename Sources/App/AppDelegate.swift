import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    private var menuBar: MenuBarController?
    private var panel: HistoryPanelController?
    private var settingsWindow: SettingsWindowController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Фоновое приложение: без иконки в Dock и без меню-бара приложения.
        // Дублирует LSUIElement из Info.plist — на случай запуска вне бандла.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment: AppEnvironment
        do {
            environment = try AppEnvironment()
        } catch {
            presentFatalError(error)
            return
        }
        self.environment = environment

        let panel = HistoryPanelController(
            viewModel: environment.viewModel,
            settings: environment.settings
        )
        self.panel = panel

        let settingsWindow = SettingsWindowController(
            settings: environment.settings,
            store: environment.store
        )
        self.settingsWindow = settingsWindow

        let menuBar = MenuBarController(settings: environment.settings, store: environment.store)
        menuBar.onOpenHistory = { [weak panel] in panel?.show() }
        menuBar.onOpenSettings = { [weak self] in self?.openSettings() }
        menuBar.onClearHistory = { [weak self] in self?.confirmClearHistory() }
        self.menuBar = menuBar

        environment.onHotKeyErrorChange = { [weak self, weak environment] in
            self?.settingsWindow?.hotKeyErrorMessage = environment?.hotKeyErrorMessage
        }

        environment.start { [weak panel] in
            panel?.toggle()
        }

        settingsWindow.hotKeyErrorMessage = environment.hotKeyErrorMessage
        Log.app.info("ClipFlow launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment?.invalidate()
    }

    /// Повторный запуск (например, двойной клик по иконке) открывает историю,
    /// а не создаёт второй экземпляр.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        panel?.show()
        return false
    }

    // MARK: - Actions

    @objc func openSettings() {
        settingsWindow?.show()
    }

    private func confirmClearHistory() {
        guard let environment else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = """
        \(environment.store.unpinnedItems.count) items will be deleted. \
        Pinned items are kept. This cannot be undone.
        """
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        environment.store.clearHistory(keepingPinned: true)
    }

    /// Единственный случай, когда приложение не может работать: недоступно
    /// локальное хранилище. Показываем понятную причину и выходим,
    /// вместо тихого запуска в нерабочем состоянии.
    private func presentFatalError(_ error: Error) {
        Log.app.critical("Launch failed: \(error.localizedDescription, privacy: .public)")

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = (error as? AppError)?.errorDescription ?? "ClipFlow couldn’t start."
        alert.informativeText = (error as? AppError)?.recoverySuggestion
            ?? error.localizedDescription
        alert.addButton(withTitle: "Quit")

        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        alert.runModal()
        NSApp.terminate(nil)
    }
}
