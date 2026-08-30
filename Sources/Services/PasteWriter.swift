import AppKit
import ApplicationServices

/// Запись в системный буфер. Единственное место, где вызывается
/// `NSPasteboard.clearContents()`.
@MainActor
final class PasteWriter {
    enum TextVariant: Identifiable {
        case original
        case trimmed
        case singleLine
        case markdownLink

        var id: String { title }

        var title: String {
            switch self {
            case .original: "Copy"
            case .trimmed: "Copy Trimmed"
            case .singleLine: "Copy as Single Line"
            case .markdownLink: "Copy as Markdown Link"
            }
        }

        func apply(to text: String) -> String {
            switch self {
            case .original:
                text
            case .trimmed:
                text.trimmingCharacters(in: .whitespacesAndNewlines)
            case .singleLine:
                text.split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .joined(separator: " ")
            case .markdownLink:
                "[\(URL(string: text)?.host ?? text)](\(text))"
            }
        }
    }

    private let pasteboard: NSPasteboard
    private let writeTracker: PasteboardWriteTracker
    private let imageStorage: ImageStorage

    init(
        pasteboard: NSPasteboard = .general,
        writeTracker: PasteboardWriteTracker,
        imageStorage: ImageStorage
    ) {
        self.pasteboard = pasteboard
        self.writeTracker = writeTracker
        self.imageStorage = imageStorage
    }

    /// Возвращает false, если содержимое элемента не удалось прочитать
    /// (например, файл изображения был удалён извне).
    @discardableResult
    func write(_ item: ClipboardItem, textVariant: TextVariant = .original) async -> Bool {
        if let text = item.text {
            write(text: textVariant.apply(to: text))
            return true
        }
        guard let name = item.imageFileName,
              let data = await imageStorage.data(forImageNamed: name)
        else {
            Log.app.warning("Image payload unavailable for item")
            return false
        }
        write(imageData: data, format: item.imageFormat)
        return true
    }

    func write(text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        markOwnWrite()
    }

    func write(imageData: Data, format: ImageFormat) {
        pasteboard.clearContents()
        pasteboard.setData(imageData, forType: NSPasteboard.PasteboardType(format.utType.identifier))
        // Дублируем в PNG/TIFF: часть приложений умеет только их.
        if format != .png, let png = pngRepresentation(of: imageData) {
            pasteboard.setData(png, forType: .png)
        }
        markOwnWrite()
    }

    /// Симуляция ⌘V. Работает только при выданном доступе к Accessibility,
    /// поэтому вызов безопасен: без прав просто ничего не произойдёт.
    func pasteIntoFrontmostApp() {
        guard AXIsProcessTrusted() else {
            Log.app.info("Auto-paste skipped: accessibility permission not granted")
            return
        }
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let vKey: CGKeyCode = 0x09

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }

    static func requestAccessibilityPermission() {
        // Using the documented key spelling avoids importing the SDK's mutable
        // C global into Swift 6 strict-concurrency checking.
        let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    // MARK: - Private

    private func markOwnWrite() {
        // Плюс маркерный тип: если changeCount проскочит между опросами,
        // читатель всё равно опознает нашу запись и не задублирует элемент.
        pasteboard.setData(Data(), forType: PasteboardReader.ownershipType)
        writeTracker.markOwnWrite(changeCount: pasteboard.changeCount)
    }

    private func pngRepresentation(of data: Data) -> Data? {
        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
