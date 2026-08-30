import AppKit

/// Menu bar — основная и единственная постоянная точка входа.
///
/// AppKit `NSStatusItem` вместо SwiftUI `MenuBarExtra`: меню строится
/// динамически (состояние Pause, счётчик элементов, актуальный хоткей),
/// а действия должны работать даже когда ни одно окно не открыто.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let settings: SettingsStore
    private let store: ClipboardStore

    var onOpenHistory: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onClearHistory: (() -> Void)?

    init(settings: SettingsStore, store: ClipboardStore) {
        self.settings = settings
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "list.clipboard",
                accessibilityDescription: "ClipFlow clipboard history"
            )
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    /// Меню перестраивается при каждом открытии — состояние всегда актуально.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let open = NSMenuItem(
            title: "Open Clipboard History",
            action: #selector(openHistory),
            keyEquivalent: ""
        )
        open.target = self
        open.image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: nil)
        menu.addItem(open)

        let shortcut = NSMenuItem(title: "Shortcut: \(settings.hotKey.displayString)", action: nil, keyEquivalent: "")
        shortcut.isEnabled = false
        menu.addItem(shortcut)

        menu.addItem(.separator())

        let count = NSMenuItem(
            title: "\(store.unpinnedItems.count) recent · \(store.pinnedItems.count) pinned",
            action: nil,
            keyEquivalent: ""
        )
        count.isEnabled = false
        menu.addItem(count)

        let pause = NSMenuItem(
            title: settings.isMonitoringPaused ? "Resume Monitoring" : "Pause Monitoring",
            action: #selector(togglePause),
            keyEquivalent: ""
        )
        pause.target = self
        pause.image = NSImage(
            systemSymbolName: settings.isMonitoringPaused ? "play.circle" : "pause.circle",
            accessibilityDescription: nil
        )
        menu.addItem(pause)

        let clear = NSMenuItem(title: "Clear History…", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quit = NSMenuItem(title: "Quit ClipFlow", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: - Actions

    @objc private func openHistory() { onOpenHistory?() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func clearHistory() { onClearHistory?() }

    @objc private func togglePause() {
        settings.isMonitoringPaused.toggle()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
