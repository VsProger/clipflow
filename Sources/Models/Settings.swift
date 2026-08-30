import AppKit
import Foundation

// MARK: - Setting value types

enum DuplicateHandling: String, CaseIterable, Identifiable, Sendable {
    /// Рекомендуемое поведение: существующий элемент поднимается наверх, счётчик +1.
    case moveToTop
    /// Не двигать: полезно, если пользователь ориентируется по позиции в списке.
    case keepOldest
    /// Полный журнал, включая повторы.
    case allowDuplicates

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .moveToTop: "Move existing item to top"
        case .keepOldest: "Keep original position"
        case .allowDuplicates: "Keep every copy"
        }
    }

    var explanation: String {
        switch self {
        case .moveToTop: "Recommended. Copying the same thing twice won’t use up two slots."
        case .keepOldest: "The item stays where it is; history order never shifts."
        case .allowDuplicates: "Every copy becomes a separate entry and consumes a slot."
        }
    }
}

enum RetentionPeriod: String, CaseIterable, Identifiable, Sendable {
    case never, oneHour, oneDay, sevenDays, thirtyDays

    var id: String { rawValue }

    var timeInterval: TimeInterval? {
        switch self {
        case .never: nil
        case .oneHour: 3_600
        case .oneDay: 86_400
        case .sevenDays: 7 * 86_400
        case .thirtyDays: 30 * 86_400
        }
    }

    var displayName: String {
        switch self {
        case .never: "Never"
        case .oneHour: "After 1 hour"
        case .oneDay: "After 1 day"
        case .sevenDays: "After 7 days"
        case .thirtyDays: "After 30 days"
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

struct KeyCombo: Codable, Equatable, Sendable {
    var keyCode: UInt16
    var modifierFlags: UInt

    static let `default` = KeyCombo(
        keyCode: 0x09, // V
        modifierFlags: NSEvent.ModifierFlags([.command, .shift]).rawValue
    )

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlags).intersection(.deviceIndependentFlagsMask)
    }

    var displayString: String {
        KeyCodeTranslator.displayString(keyCode: keyCode, modifiers: modifiers)
    }
}

// MARK: - Store

extension Notification.Name {
    static let clipFlowSettingsDidChange = Notification.Name("ClipFlowSettingsDidChange")
}

enum SettingsChange: String {
    case hotKey, appearance, monitoring, retention, limit, launchAtLogin
}

/// Настройки. Один источник правды, персистится в UserDefaults.
/// Кросс-модульные изменения (хоткей, тема, лимиты) рассылаются нотификацией —
/// подписчики живут в `AppEnvironment`, чтобы UI не знал о сервисах.
@Observable
@MainActor
final class SettingsStore {
    // MARK: General
    var hotKey: KeyCombo {
        didSet { persist(hotKey, .hotKey); announce(.hotKey) }
    }

    var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin); announce(.launchAtLogin) }
    }

    var isMonitoringPaused: Bool {
        didSet { defaults.set(isMonitoringPaused, forKey: Key.isMonitoringPaused); announce(.monitoring) }
    }

    // MARK: Storage
    /// Лимит НЕзакреплённых элементов. Закреплённые не входят в этот бюджет.
    var historyLimit: Int {
        didSet {
            historyLimit = max(1, min(historyLimit, 1_000))
            defaults.set(historyLimit, forKey: Key.historyLimit)
            announce(.limit)
        }
    }

    var retentionPeriod: RetentionPeriod {
        didSet { defaults.set(retentionPeriod.rawValue, forKey: Key.retentionPeriod); announce(.retention) }
    }

    // MARK: Appearance
    var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance); announce(.appearance) }
    }

    // MARK: Behavior
    var duplicateHandling: DuplicateHandling {
        didSet { defaults.set(duplicateHandling.rawValue, forKey: Key.duplicateHandling) }
    }

    var closesAfterSelection: Bool {
        didSet { defaults.set(closesAfterSelection, forKey: Key.closesAfterSelection) }
    }

    var copiesOnSingleClick: Bool {
        didSet { defaults.set(copiesOnSingleClick, forKey: Key.copiesOnSingleClick) }
    }

    var capturesImages: Bool {
        didSet { defaults.set(capturesImages, forKey: Key.capturesImages) }
    }

    /// Авто-вставка (⌘V) после выбора. Требует Accessibility, поэтому по умолчанию выключено.
    var pastesAutomatically: Bool {
        didSet { defaults.set(pastesAutomatically, forKey: Key.pastesAutomatically) }
    }

    /// Bundle ID приложений, из которых копирование не записывается.
    var excludedBundleIDs: [String] {
        didSet { defaults.set(excludedBundleIDs, forKey: Key.excludedBundleIDs) }
    }

    /// Предохранитель для закреплённых: pin не должен превращаться в утечку диска.
    let pinnedLimit = 200

    private let defaults: UserDefaults
    private var isLoading = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Key.hotKey),
           let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            hotKey = combo
        } else {
            hotKey = .default
        }

        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        isMonitoringPaused = defaults.bool(forKey: Key.isMonitoringPaused)
        historyLimit = defaults.object(forKey: Key.historyLimit) as? Int ?? 30
        retentionPeriod = RetentionPeriod(rawValue: defaults.string(forKey: Key.retentionPeriod) ?? "") ?? .never
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        duplicateHandling = DuplicateHandling(rawValue: defaults.string(forKey: Key.duplicateHandling) ?? "") ?? .moveToTop
        closesAfterSelection = defaults.object(forKey: Key.closesAfterSelection) as? Bool ?? true
        copiesOnSingleClick = defaults.object(forKey: Key.copiesOnSingleClick) as? Bool ?? true
        capturesImages = defaults.object(forKey: Key.capturesImages) as? Bool ?? true
        pastesAutomatically = defaults.bool(forKey: Key.pastesAutomatically)
        excludedBundleIDs = defaults.stringArray(forKey: Key.excludedBundleIDs) ?? SettingsStore.defaultExcludedBundleIDs

        isLoading = false
    }

    /// Известные менеджеры паролей исключаются по умолчанию — в дополнение
    /// к проверке `org.nspasteboard.ConcealedType`, которую они обычно ставят.
    static let defaultExcludedBundleIDs = [
        "com.apple.keychainaccess",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.sindresorhus.Secretive",
        "in.sinew.Enpass-Desktop",
    ]

    private func persist(_ combo: KeyCombo, _ change: SettingsChange) {
        guard let data = try? JSONEncoder().encode(combo) else { return }
        defaults.set(data, forKey: Key.hotKey)
    }

    private func announce(_ change: SettingsChange) {
        guard !isLoading else { return }
        NotificationCenter.default.post(
            name: .clipFlowSettingsDidChange,
            object: self,
            userInfo: ["change": change.rawValue]
        )
    }

    private enum Key {
        static let hotKey = "hotKey"
        static let launchAtLogin = "launchAtLogin"
        static let isMonitoringPaused = "isMonitoringPaused"
        static let historyLimit = "historyLimit"
        static let retentionPeriod = "retentionPeriod"
        static let appearance = "appearance"
        static let duplicateHandling = "duplicateHandling"
        static let closesAfterSelection = "closesAfterSelection"
        static let copiesOnSingleClick = "copiesOnSingleClick"
        static let capturesImages = "capturesImages"
        static let pastesAutomatically = "pastesAutomatically"
        static let excludedBundleIDs = "excludedBundleIDs"
    }
}
