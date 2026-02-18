import AppKit
import Carbon.HIToolbox

/// Replaces typed text by simulating backspaces and pasting new text.
final class TextReplacer {

    /// Replace the last `count` characters with `newText`.
    func replace(characterCount count: Int, with newText: String) {
        // Step 1: Delete the old characters using backspace events
        deleteCharacters(count: count)

        // Small delay to let the backspaces take effect
        usleep(50_000) // 50ms

        // Step 2: Insert new text via clipboard
        pasteText(newText)
    }

    /// Simulate Cmd+V (paste from current clipboard).
    func sendPaste() {
        sendKeyEvent(keyCode: UInt16(kVK_ANSI_V), keyDown: true, flags: .maskCommand)
        sendKeyEvent(keyCode: UInt16(kVK_ANSI_V), keyDown: false, flags: .maskCommand)
    }

    /// Simulate Cmd+C (copy selection to clipboard).
    func sendCopy() {
        sendKeyEvent(keyCode: UInt16(kVK_ANSI_C), keyDown: true, flags: .maskCommand)
        sendKeyEvent(keyCode: UInt16(kVK_ANSI_C), keyDown: false, flags: .maskCommand)
    }

    /// Send `count` backspace key events.
    private func deleteCharacters(count: Int) {
        for _ in 0..<count {
            sendKeyEvent(keyCode: UInt16(kVK_Delete), keyDown: true)
            sendKeyEvent(keyCode: UInt16(kVK_Delete), keyDown: false)
            usleep(5_000) // 5ms between keystrokes
        }
    }

    /// Paste text using the clipboard (Cmd+V), saving and restoring clipboard.
    private func pasteText(_ text: String) {
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        sendPaste()

        // Restore clipboard after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            pasteboard.clearContents()
            if let old = oldContents {
                pasteboard.setString(old, forType: .string)
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
