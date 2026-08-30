import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Панель истории.
///
/// `.nonactivatingPanel` — ключевое решение: приложение, куда пользователь
/// будет вставлять, не теряет активность. При этом `canBecomeKey` переопределён,
/// чтобы строка поиска могла принимать ввод.
final class HistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class HistoryPanelController {
    private let viewModel: ClipboardViewModel
    private let settings: SettingsStore
    private var panel: HistoryPanel?
    private var keyMonitor: Any?
    private var outsideClickMonitor: Any?
    private var previousApp: NSRunningApplication?

    private let panelSize = CGSize(width: 420, height: 520)

    var isVisible: Bool { panel?.isVisible ?? false }

    init(viewModel: ClipboardViewModel, settings: SettingsStore) {
        self.viewModel = viewModel
        self.settings = settings
        viewModel.onRequestClose = { [weak self] in self?.hide() }
    }

    // MARK: - Presentation

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        // Запоминаем, куда возвращать фокус: сюда же уйдёт авто-вставка.
        previousApp = NSWorkspace.shared.frontmostApplication

        let panel = panel ?? makePanel()
        self.panel = panel

        viewModel.prepareForPresentation()
        position(panel)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        installMonitors()
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        removeMonitors()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.09
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            panel.orderOut(nil)
            // Возвращаем активность приложению, из которого пришёл пользователь.
            self?.previousApp?.activate()
            self?.previousApp = nil
        }
    }

    // MARK: - Construction

    private func makePanel() -> HistoryPanel {
        let panel = HistoryPanel(
            contentRect: CGRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        // Историю буфера незачем показывать в screen sharing и записи экрана.
        panel.sharingType = .none

        let root = HistoryView(viewModel: viewModel)
            .environment(settings)
            .frame(width: panelSize.width, height: panelSize.height)

        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: panelSize)
        panel.contentView = hosting
        return panel
    }

    /// Панель появляется на экране с курсором, в верхней трети —
    /// ближе к взгляду пользователя, чем геометрический центр.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        let origin = CGPoint(
            x: visible.midX - panelSize.width / 2,
            y: visible.midY - panelSize.height / 2 + visible.height * 0.12
        )
        panel.setFrame(CGRect(origin: origin, size: panelSize), display: false)
    }

    // MARK: - Event monitors

    /// Локальный монитор, а не `.onKeyPress`: фокус всегда в строке поиска,
    /// поэтому стрелки и Enter нужно перехватить раньше текстового поля.
    private func installMonitors() {
        guard keyMonitor == nil else { return }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
            .leftMouseDown, .rightMouseDown
        ]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        keyMonitor = nil
        outsideClickMonitor = nil
    }

    /// true — событие обработано и не должно идти дальше.
    private func handle(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCommand = modifiers == .command

        switch Int(event.keyCode) {
        case kVK_Escape:
            if viewModel.previewItem != nil {
                viewModel.previewItem = nil
            } else if viewModel.pendingClearConfirmation {
                viewModel.pendingClearConfirmation = false
            } else if !viewModel.query.isEmpty {
                viewModel.query = ""     // первый Escape чистит поиск,
                viewModel.normalizeSelection()
            } else {
                hide()                   // второй — закрывает окно
            }
            return true

        case kVK_UpArrow:
            viewModel.moveSelection(by: modifiers.contains(.command) ? -Int.max / 2 : -1)
            return true

        case kVK_DownArrow:
            viewModel.moveSelection(by: modifiers.contains(.command) ? Int.max / 2 : 1)
            return true

        case kVK_Return, kVK_ANSI_KeypadEnter:
            if viewModel.pendingClearConfirmation {
                viewModel.confirmClearHistory()
            } else if viewModel.previewItem != nil {
                viewModel.previewItem = nil
            } else {
                viewModel.activateSelection()
            }
            return true

        case kVK_Delete:
            // Плоский Backspace редактирует поиск, поэтому удаление — ⌘⌫.
            // Исключение: поиск пуст, редактировать нечего.
            if isCommand || viewModel.query.isEmpty {
                viewModel.deleteSelection()
                return true
            }
            return false

        case kVK_ANSI_Y where isCommand, kVK_Space where viewModel.query.isEmpty:
            viewModel.previewSelection()
            return true

        case kVK_ANSI_P where isCommand:
            if let item = viewModel.selectedItem { viewModel.togglePin(item) }
            return true

        case kVK_ANSI_K where isCommand:
            viewModel.query = ""
            viewModel.normalizeSelection()
            return true

        default:
            return false
        }
    }
}
