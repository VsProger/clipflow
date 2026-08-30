import Foundation
import OSLog

/// Централизованное логирование.
///
/// Правило проекта: содержимое буфера обмена НИКОГДА не логируется — ни целиком,
/// ни фрагментами. Разрешено логировать только тип элемента, размер и результат
/// операции. Любая строка, полученная из NSPasteboard, помечается `.private`.
enum Log {
    static let app = Logger(subsystem: subsystem, category: "app")
    static let monitor = Logger(subsystem: subsystem, category: "monitor")
    static let store = Logger(subsystem: subsystem, category: "store")
    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let ui = Logger(subsystem: subsystem, category: "ui")

    private static let subsystem = Bundle.main.bundleIdentifier ?? "app.clipflow"
}

enum AppError: LocalizedError {
    case storageUnavailable(underlying: Error)
    case imageDecodingFailed
    case imageEncodingFailed
    case diskWriteFailed(underlying: Error)
    case insufficientDiskSpace(required: Int)
    case hotKeyRegistrationFailed(status: Int32)

    var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            "ClipFlow couldn’t open its local database."
        case .imageDecodingFailed:
            "The copied image could not be read."
        case .imageEncodingFailed:
            "The copied image could not be converted for storage."
        case .diskWriteFailed:
            "ClipFlow couldn’t write to disk."
        case .insufficientDiskSpace:
            "There isn’t enough free disk space to store this item."
        case .hotKeyRegistrationFailed:
            "The global shortcut is already in use by another app."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .storageUnavailable:
            "Quit ClipFlow and try again. If the problem persists, remove ~/Library/Application Support/ClipFlow."
        case .insufficientDiskSpace:
            "Free up some space, or turn off image capture in Settings → Behavior."
        case .hotKeyRegistrationFailed:
            "Pick a different shortcut in Settings → General."
        default:
            nil
        }
    }
}
