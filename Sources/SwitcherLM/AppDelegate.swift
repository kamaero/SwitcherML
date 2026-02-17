import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let statusBarController = StatusBarController()
    private let keyboardMonitor = KeyboardMonitor()
    private let spellCheckService = SpellCheckService()
    private let textReplacer = TextReplacer()
    private let mlService = MLService()
    private let exceptionsManager = ExceptionsManager()
    private var exceptionsWindowController: ExceptionsWindowController?

    /// Tracks whether we're currently performing a replacement (to ignore our own events).
    private var isReplacing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        )

        if !trusted {
            print("Accessibility access is required. Please grant permission in System Settings.")
        }

        statusBarController.setup()

        statusBarController.onToggleEnabled = { [weak self] enabled in
            self?.keyboardMonitor.isEnabled = enabled
        }

        statusBarController.onShowExceptions = { [weak self] in
            self?.showExceptionsWindow()
        }

        mlService.onAutoException = { [weak self] word in
            self?.exceptionsManager.add(word)
            print("Auto-exception added: \"\(word)\"")
        }

        // Should we convert this word?
        keyboardMonitor.shouldConvert = { [weak self] word in
            guard let self, !self.isReplacing else { return nil }

            if self.exceptionsManager.contains(word) {
                return nil
            }

            return self.spellCheckService.suggestConversion(
                for: word,
                exceptions: self.exceptionsManager.exceptions
            )
        }

        // Perform the replacement. Returns true if replacement happened.
        keyboardMonitor.onReplace = { [weak self] original, replacement, boundary in
            guard let self, !self.isReplacing else { return false }
            self.isReplacing = true

            // The boundary event is suppressed by KeyboardMonitor (returns nil).
            // So the text on screen is just the original word — delete it and paste replacement + boundary.
            self.textReplacer.replace(
                characterCount: original.count,
                with: replacement + boundary
            )

            // Store for backspace-rejection tracking
            self.keyboardMonitor.lastConversion = (original: original, replacement: replacement)

            // Switch keyboard layout to match the target language
            InputSourceSwitcher.switchToMatch(convertedText: replacement)

            self.statusBarController.incrementStats()
            self.mlService.recordAccepted(word: original)

            print("Replaced: \"\(original)\" → \"\(replacement)\" (boundary: \(boundary.debugDescription))")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.isReplacing = false
            }

            return true
        }

        // User rejected a conversion (backspaced + retyped original)
        keyboardMonitor.onConversionRejected = { [weak self] word in
            guard let self else { return }
            self.mlService.recordRejection(word: word)
            self.statusBarController.incrementRejections()
            print("Conversion rejected for: \"\(word)\"")
        }

        // Double-LShift force conversion
        keyboardMonitor.onForceConvert = { [weak self] in
            self?.handleForceConvert()
        }

        keyboardMonitor.isEnabled = true
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyboardMonitor.isEnabled = false
    }

    // MARK: - Force conversion (Double-LShift)

    private func handleForceConvert() {
        // Try to get selected text first
        if let selectedText = getSelectedText(), !selectedText.isEmpty {
            forceConvertSelection(selectedText)
            return
        }

        // No selection — convert current in-progress word, or last completed word
        let lastWord = keyboardMonitor.takeCurrentWord() ?? keyboardMonitor.lastTypedWord
        guard !lastWord.isEmpty else { return }

        let converted = LayoutConverter.convertPreservingCase(lastWord)
        guard converted != lastWord else { return }

        isReplacing = true
        textReplacer.replace(characterCount: lastWord.count, with: converted)
        InputSourceSwitcher.switchToMatch(convertedText: converted)
        statusBarController.incrementStats()
        print("Force-converted: \"\(lastWord)\" → \"\(converted)\"")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isReplacing = false
        }
    }

    private func forceConvertSelection(_ text: String) {
        let converted = LayoutConverter.convertPreservingCase(text)
        guard converted != text else { return }

        isReplacing = true

        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(converted, forType: .string)

        textReplacer.sendPaste()

        InputSourceSwitcher.switchToMatch(convertedText: converted)
        statusBarController.incrementStats()
        print("Force-converted selection: \"\(text)\" → \"\(converted)\"")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            pasteboard.clearContents()
            if let old = oldContents {
                pasteboard.setString(old, forType: .string)
            }
            self?.isReplacing = false
        }
    }

    private func getSelectedText() -> String? {
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)
        let oldChangeCount = pasteboard.changeCount

        textReplacer.sendCopy()
        usleep(100_000) // 100ms for clipboard to update

        guard pasteboard.changeCount != oldChangeCount else {
            return nil
        }

        let selectedText = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        if let old = oldContents {
            pasteboard.setString(old, forType: .string)
        }

        return selectedText
    }

    // MARK: - Exceptions window

    private func showExceptionsWindow() {
        if exceptionsWindowController == nil {
            exceptionsWindowController = ExceptionsWindowController(manager: exceptionsManager)
        }
        exceptionsWindowController?.showWindow()
    }
}
