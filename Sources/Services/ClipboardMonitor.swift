import AppKit

/// Отслеживает `NSPasteboard.general.changeCount`.
///
/// Уведомлений об изменении буфера в macOS нет, поэтому единственный путь — опрос.
/// Сама проверка changeCount — это IPC-запрос без чтения данных, дешёвая операция;
/// дорогое чтение payload происходит только когда счётчик реально изменился.
///
/// Интервал адаптивный:
///   • `activeInterval` (0.25 с) — первые 15 с после последнего изменения;
///   • `idleInterval` (1.0 с) — в простое.
/// Плюс полная остановка при блокировке экрана и уходе системы в сон.
@MainActor
final class ClipboardMonitor {
    private enum Cadence {
        static let active: Duration = .milliseconds(250)
        static let idle: Duration = .seconds(1)
        static let activityWindow: TimeInterval = 15
    }

    private let pasteboard: NSPasteboard
    private let writeTracker: PasteboardWriteTracker
    private let settings: SettingsStore

    private var pollingTask: Task<Void, Never>?
    private var lastChangeCount: Int
    private var lastCaptureAt: Date = .distantPast
    private var isSuspendedBySystem = false
    private var observers: [any NSObjectProtocol] = []

    /// Вызывается на MainActor при новом содержимом буфера.
    var onCapture: ((ClipboardCapture) -> Void)?

    private(set) var isRunning = false

    init(
        pasteboard: NSPasteboard = .general,
        writeTracker: PasteboardWriteTracker,
        settings: SettingsStore
    ) {
        self.pasteboard = pasteboard
        self.writeTracker = writeTracker
        self.settings = settings
        // Стартуем с текущего значения: содержимое, лежавшее в буфере до запуска,
        // в историю не попадает — так пользователь не удивляется чужим элементам.
        self.lastChangeCount = pasteboard.changeCount
        registerSystemObservers()
    }

    deinit {
        // В deinit (nonisolated) допустимо трогать только Sendable-свойства,
        // поэтому снятие наблюдателей вынесено в явный invalidate().
        pollingTask?.cancel()
    }

    /// Освобождает наблюдателей. Вызывается при завершении приложения.
    func invalidate() {
        stop()
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observers.removeAll()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        resumePollingIfNeeded()
        Log.monitor.info("Clipboard monitoring started")
    }

    func stop() {
        isRunning = false
        pollingTask?.cancel()
        pollingTask = nil
        Log.monitor.info("Clipboard monitoring stopped")
    }

    /// Применяет актуальное состояние настроек (Pause Monitoring).
    func applySettings() {
        if settings.isMonitoringPaused {
            stop()
        } else {
            start()
        }
    }

    // MARK: - Polling loop

    private func resumePollingIfNeeded() {
        guard isRunning, !isSuspendedBySystem, pollingTask == nil else { return }
        // Пропускаем всё, что появилось в буфере пока мониторинг был выключен.
        lastChangeCount = pasteboard.changeCount

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.poll()
                let interval = Date.now.timeIntervalSince(self.lastCaptureAt) < Cadence.activityWindow
                    ? Cadence.active
                    : Cadence.idle
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
            }
        }
    }

    private func suspendPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func poll() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        // Наша собственная запись в буфер — не событие пользователя.
        guard !writeTracker.isOwnWrite(changeCount: changeCount) else { return }

        let reader = PasteboardReader(
            capturesImages: settings.capturesImages,
            excludedBundleIDs: Set(settings.excludedBundleIDs)
        )
        guard let capture = reader.read(from: pasteboard) else { return }

        lastCaptureAt = .now
        Log.monitor.debug("Captured item, bytes: \(capture.byteSize, privacy: .public)")
        onCapture?(capture)
    }

    // MARK: - System state

    private func registerSystemObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.setSystemSuspended(true) }
        })
        observers.append(workspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.setSystemSuspended(false) }
        })

        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.setSystemSuspended(true) }
        })
        observers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.setSystemSuspended(false) }
        })
    }

    private func setSystemSuspended(_ suspended: Bool) {
        guard isSuspendedBySystem != suspended else { return }
        isSuspendedBySystem = suspended
        if suspended {
            suspendPolling()
        } else {
            resumePollingIfNeeded()
        }
    }
}

/// Общий объект между писателем и монитором: помогает отличить
/// собственную запись в буфер от действия пользователя.
@MainActor
final class PasteboardWriteTracker {
    private var ownChangeCounts: Set<Int> = []

    func markOwnWrite(changeCount: Int) {
        ownChangeCounts.insert(changeCount)
        if ownChangeCounts.count > 16 {
            ownChangeCounts = Set(ownChangeCounts.sorted().suffix(8))
        }
    }

    func isOwnWrite(changeCount: Int) -> Bool {
        ownChangeCounts.remove(changeCount) != nil
    }
}
