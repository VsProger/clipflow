import AppKit
import Carbon.HIToolbox

/// Глобальный хоткей через `RegisterEventHotKey`.
///
/// Почему Carbon, а не `NSEvent.addGlobalMonitorForEvents`: глобальный монитор
/// требует разрешения Accessibility и видит все нажатия в системе. Carbon-API
/// регистрирует конкретную комбинацию, работает без дополнительных прав,
/// внутри App Sandbox и не является deprecated — это до сих пор единственный
/// поддерживаемый способ получить system-wide hotkey на macOS.
@MainActor
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static let signature: OSType = 0x434C_4650 // 'CLFP'
    private static let identifier: UInt32 = 1

    var onPress: (() -> Void)?

    init() {
        installHandler()
        // Диспетчер гарантирует вызов на main thread, поэтому изоляцию
        // можно утвердить, не заводя лишний асинхронный хоп.
        HotKeyDispatcher.shared.register(id: Self.identifier) { [weak self] in
            MainActor.assumeIsolated { self?.onPress?() }
        }
    }

    /// Перерегистрирует комбинацию. Бросает, если её уже занял кто-то другой —
    /// UI настроек показывает это пользователю, вместо тихого «не работает».
    func register(_ combo: KeyCombo) throws {
        unregister()

        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.identifier)
        let status = RegisterEventHotKey(
            UInt32(combo.keyCode),
            KeyCodeTranslator.carbonModifiers(from: combo.modifiers),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else {
            Log.hotkey.error("RegisterEventHotKey failed with status \(status, privacy: .public)")
            throw AppError.hotKeyRegistrationFailed(status: status)
        }
        hotKeyRef = reference
        Log.hotkey.info("Registered shortcut \(combo.displayString, privacy: .public)")
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Обработчик — C-функция без захвата контекста; маршрутизация
        // выполняется через синглтон-диспетчер.
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, _ -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                HotKeyDispatcher.shared.dispatch(id: hotKeyID.id)
                return noErr
            },
            1,
            &eventType,
            nil,
            &handlerRef
        )
    }
}

/// Мост между C-callback и Swift-миром.
final class HotKeyDispatcher: @unchecked Sendable {
    static let shared = HotKeyDispatcher()

    private let lock = NSLock()
    private var handlers: [UInt32: @Sendable () -> Void] = [:]

    private init() {}

    func register(id: UInt32, handler: @escaping @Sendable () -> Void) {
        lock.withLock { handlers[id] = handler }
    }

    func unregister(id: UInt32) {
        lock.withLock { handlers[id] = nil }
    }

    /// Carbon вызывает обработчик на main run loop, но hop делаем явно,
    /// чтобы не зависеть от деталей реализации.
    func dispatch(id: UInt32) {
        let handler = lock.withLock { handlers[id] }
        guard let handler else { return }
        if Thread.isMainThread {
            handler()
        } else {
            DispatchQueue.main.async { handler() }
        }
    }
}
