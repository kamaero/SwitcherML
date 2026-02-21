import AppKit
import Carbon.HIToolbox

/// Replaces typed text by simulating backspaces then injecting new text via CGEvent.
final class TextReplacer {

    /// Replace the last `count` characters with `newText`.
    /// Backspaces are posted synchronously; text injection is scheduled 50 ms later
    /// to give the application time to process the deletions.
    func replace(characterCount count: Int, with newText: String) {
        deleteCharacters(count: count)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.injectText(newText)
        }
    }

    /// Simulate Cmd+V (paste from current clipboard). Used for force-convert of selections.
    func sendPaste() {
        sendKeyEvent(keyCode: UInt16(kVK_ANSI_V), keyDown: true, flags: .maskCommand)
        sendKeyEvent(keyCode: UInt16(kVK_ANSI_V), keyDown: false, flags: .maskCommand)
    }

    /// Simulate Cmd+C (copy selection to clipboard).
    func sendCopy() {
        sendKeyEvent(keyCode: UInt16(kVK_ANSI_C), keyDown: true, flags: .maskCommand)
        sendKeyEvent(keyCode: UInt16(kVK_ANSI_C), keyDown: false, flags: .maskCommand)
    }

    // MARK: - Private

    /// Send `count` backspace key events.
    private func deleteCharacters(count: Int) {
        for _ in 0..<count {
            sendKeyEvent(keyCode: UInt16(kVK_Delete), keyDown: true)
            sendKeyEvent(keyCode: UInt16(kVK_Delete), keyDown: false)
        }
    }

    /// Inject text directly using CGEvent unicode string — no clipboard involved.
    /// Most macOS text inputs (Cocoa, WebKit, etc.) honour the unicode string field
    /// and insert the text at the current cursor position.
    private func injectText(_ text: String) {
        let utf16 = Array(text.utf16)
        guard !utf16.isEmpty else { return }

        utf16.withUnsafeBufferPointer { buffer in
            guard let ptr = buffer.baseAddress else { return }

            if let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) {
                event.setIntegerValueField(.eventSourceUserData, value: EventMarker.userData)
                event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: ptr)
                event.post(tap: .cghidEventTap)
            }
            if let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
                event.setIntegerValueField(.eventSourceUserData, value: EventMarker.userData)
                event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: ptr)
                event.post(tap: .cghidEventTap)
            }
        }
    }

    /// Create and post a CGEvent for a key press/release.
    private func sendKeyEvent(keyCode: UInt16, keyDown: Bool, flags: CGEventFlags = []) {
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: keyCode,
            keyDown: keyDown
        ) else { return }

        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: EventMarker.userData)
        event.post(tap: .cghidEventTap)
    }
}
