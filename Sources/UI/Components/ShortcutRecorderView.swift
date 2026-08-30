import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Поле записи горячей клавиши. AppKit, потому что SwiftUI не даёт
/// перехватить сырое нажатие с модификаторами до системной обработки.
struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var combo: KeyCombo

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.combo = combo
        view.onChange = { newValue in combo = newValue }
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.combo = combo
        view.needsDisplay = true
    }

    final class RecorderView: NSView {
        var combo: KeyCombo = .default
        var onChange: ((KeyCombo) -> Void)?

        private var isRecording = false {
            didSet { needsDisplay = true }
        }

        override var acceptsFirstResponder: Bool { true }
        override var intrinsicContentSize: NSSize { NSSize(width: 130, height: 24) }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            isRecording = true
        }

        override func resignFirstResponder() -> Bool {
            isRecording = false
            return true
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            // Пока идёт запись, перехватываем даже системные ⌘-комбинации.
            guard isRecording else { return false }
            return capture(event)
        }

        override func keyDown(with event: NSEvent) {
            guard isRecording, capture(event) else {
                super.keyDown(with: event)
                return
            }
        }

        private func capture(_ event: NSEvent) -> Bool {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if Int(event.keyCode) == kVK_Escape, modifiers.isEmpty {
                isRecording = false
                return true
            }

            // Хоткей без модификаторов забирал бы обычные нажатия у всей системы.
            let required: NSEvent.ModifierFlags = [.command, .control, .option]
            guard !modifiers.intersection(required).isEmpty else { return false }

            let newCombo = KeyCombo(keyCode: event.keyCode, modifierFlags: modifiers.rawValue)
            combo = newCombo
            onChange?(newCombo)
            isRecording = false
            return true
        }

        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.controlBackgroundColor).setFill()
            path.fill()
            (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
            path.lineWidth = isRecording ? 2 : 1
            path.stroke()

            let title = isRecording ? "Press keys…" : combo.displayString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium),
                .foregroundColor: isRecording ? NSColor.secondaryLabelColor : NSColor.labelColor,
            ]
            let string = NSAttributedString(string: title, attributes: attributes)
            let size = string.size()
            string.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
        }
    }
}
