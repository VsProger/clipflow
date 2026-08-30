import AppKit
import SwiftUI

/// Окно настроек управляется вручную, а не сценой `Settings`:
/// у accessory-приложения нет SwiftUI App-жизненного цикла, а ручное окно
/// даёт полный контроль над активацией и не зависит от приватных селекторов.
@MainActor
final class SettingsWindowController {
    private let settings: SettingsStore
    private let store: ClipboardStore
    private var window: NSWindow?

    var hotKeyErrorMessage: String?

    init(settings: SettingsStore, store: ClipboardStore) {
        self.settings = settings
        self.store = store
    }

    func show() {
        if let window {
            reload(in: window)
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ClipFlow Settings"
        window.isReleasedWhenClosed = false
        window.center()
        // The tab selector lives in the SwiftUI content, not an NSToolbar.
        // `.preference` merges that content into the titlebar, where it
        // overlaps the traffic-light buttons on current macOS releases.
        window.toolbarStyle = .automatic
        reload(in: window)

        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func reload(in window: NSWindow) {
        let view = SettingsView(
            settings: settings,
            store: store,
            hotKeyError: hotKeyErrorMessage
        )
        window.contentView = NSHostingView(rootView: view)
        window.setContentSize(NSSize(width: 480, height: 440))
    }
}
