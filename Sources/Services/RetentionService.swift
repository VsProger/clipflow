import AppKit

/// Планировщик автоочистки. Вся логика удаления живёт в `ClipboardStore` —
/// здесь только «когда».
///
/// Раз в 5 минут — дёшево и достаточно точно для интервалов от часа.
/// Дополнительно прогоняется при выходе из сна: если Mac спал сутки,
/// просроченное должно исчезнуть сразу, а не через пять минут.
@MainActor
final class RetentionService {
    private let store: ClipboardStore
    private var timer: Task<Void, Never>?
    private var wakeObserver: (any NSObjectProtocol)?

    init(store: ClipboardStore) {
        self.store = store
    }

    deinit {
        timer?.cancel()
    }

    func invalidate() {
        timer?.cancel()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    func start() {
        guard timer == nil else { return }

        timer = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(300))
                } catch {
                    return
                }
                self?.runNow()
            }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.runNow() }
        }

        runNow()
        Task { await store.removeOrphanFiles() }
    }

    func runNow() {
        store.purgeExpired()
        store.enforceLimits()
    }
}
