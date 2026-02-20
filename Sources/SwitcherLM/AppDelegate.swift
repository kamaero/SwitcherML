import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let statusBarController = StatusBarController()
    private let keyboardMonitor = KeyboardMonitor()
    private let spellCheckService = SpellCheckService()
    private let textReplacer = TextReplacer()
    private let mlService = MLService()
    private let exceptionsManager = ExceptionsManager()
    private let settings = SettingsManager.shared
    private let focusHighlighter = FocusHighlighter()
    private var exceptionsWindowController: ExceptionsWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var skipNextWord: Bool = false

    private let undoWindow: TimeInterval = 5.0

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

        statusBarController.onShowSettings = { [weak self] in
            self?.showSettingsWindow()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsChanged),
            name: SettingsManager.didChangeNotification,
            object: nil
        )

        mlService.onAutoException = { [weak self] word in
            self?.exceptionsManager.add(word)
            print("Auto-exception added: \"\(word)\"")
        }

        // Should we convert this word?
        keyboardMonitor.shouldConvert = { [weak self] word in
            guard let self, !self.isReplacing else { return nil }

            if !self.settings.autoConvertEnabled {
                return nil
            }

            if self.skipNextWord {
                self.skipNextWord = false
                return nil
            }

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
            self.keyboardMonitor.lastConversionTime = ProcessInfo.processInfo.systemUptime
            self.keyboardMonitor.recordReplacement(original: original, replacement: replacement, boundary: boundary)

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

        keyboardMonitor.onUndoLastReplacement = { [weak self] in
            self?.handleUndoReplacement()
        }

        keyboardMonitor.onSkipNextWord = { [weak self] in
            self?.skipNextWord = true
        }

        keyboardMonitor.isEnabled = true
        focusHighlighter.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyboardMonitor.isEnabled = false
        focusHighlighter.stop()
    }

    // MARK: - Force conversion (Double-LShift)

    private func handleForceConvert() {
        // Try to get selected text first
        if let selectedText = getSelectedText(), !selectedText.isEmpty {
            forceConvertSelection(selectedText)
            return
        }
        // No selection — do nothing (double-shift reserved for selection)
        return
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

    // MARK: - Undo last replacement

    private func handleUndoReplacement() {
        guard let last = keyboardMonitor.lastReplacement else { return }
        if keyboardMonitor.hasTypedSinceReplacement { return }

        let now = ProcessInfo.processInfo.systemUptime
        if now - last.time > undoWindow { return }

        isReplacing = true
        textReplacer.replace(
            characterCount: last.replacement.count + last.boundary.count,
            with: last.original + last.boundary
        )
        keyboardMonitor.clearLastReplacement()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isReplacing = false
        }
    }

    // MARK: - Exceptions window

    private func showExceptionsWindow() {
        if exceptionsWindowController == nil {
            exceptionsWindowController = ExceptionsWindowController(manager: exceptionsManager)
        }
        exceptionsWindowController?.showWindow()
    }

    private func showSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showWindow()
    }

    @objc private func handleSettingsChanged() {
        if settings.highlightEnabled {
            focusHighlighter.start()
        } else {
            focusHighlighter.stop()
        }
    }
}
