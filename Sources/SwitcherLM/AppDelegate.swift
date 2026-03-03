import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let statusBarController = StatusBarController()
    private let keyboardMonitor = KeyboardMonitor()
    private let spellCheckService = SpellCheckService()
    private let textReplacer = TextReplacer()
    private let mlService = MLService()
    private let exceptionsManager = ExceptionsManager()
    private let appFilterManager = AppFilterManager()
    private let layoutToastPresenter = LayoutToastPresenter()
    private let screenFlasher = ScreenFlasher()
    private let settings = SettingsManager.shared
    private var exceptionsWindowController: ExceptionsWindowController?
    private var appFilterWindowController: AppFilterWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var skipNextWord: Bool = false

    // Phase 1 — context tracking
    private let contextTracker = ContextLanguageTracker()
    private let appMemory = AppLanguageMemory()

    // Phase 2 — feature collection
    private let sampleStore = SampleStore()
    private var previousWord: String = ""

    // Phase 3 — on-device ML
    private let trainer = OnDeviceTrainer()
    private var coreMLPredictor: CoreMLPredictor?

    /// Tracks whether we're currently performing a replacement (to ignore our own events).
    private var isReplacing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let trusted = AXIsProcessTrustedWithOptions(
            [promptKey: true] as CFDictionary
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

        statusBarController.onShowAppFilters = { [weak self] in
            self?.showAppFilterWindow()
        }

        statusBarController.onShowSettings = { [weak self] in
            self?.showSettingsWindow()
        }

        // Only show language badge toast for user-initiated layout changes.
        // Auto-conversions show their own toast (with word pair) directly from onReplace.
        statusBarController.onLayoutChanged = { [weak self] language in
            guard let self, !self.isReplacing else { return }
            self.layoutToastPresenter.show(language: language)
        }

        mlService.onAutoException = { [weak self] word in
            self?.exceptionsManager.add(word)
            print("Auto-exception added: \"\(word)\"")
        }

        // Load any previously trained model from disk
        if let existingModel = trainer.loadExistingModel() {
            coreMLPredictor = CoreMLPredictor(model: existingModel)
            let count = sampleStore.labeledCount
            postModelStatus("Model: On-Device ML (\(count) samples)")
            print("OnDeviceTrainer: Loaded existing model (\(count) labeled samples)")
        }

        // Wire up model-ready callback
        trainer.onModelReady = { [weak self] model in
            guard let self else { return }
            self.coreMLPredictor = CoreMLPredictor(model: model)
            let count = self.sampleStore.labeledCount
            self.postModelStatus("Model: On-Device ML (\(count) samples)")
        }

        // Should we convert this word?
        keyboardMonitor.shouldConvert = { [weak self] word in
            guard let self, !self.isReplacing else { return nil }
            guard self.settings.autoConvertEnabled else { return nil }

            // Skip password / secure text fields
            if self.isFocusedOnSecureField() { return nil }

            // Skip apps in the blacklist
            let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
            if self.appFilterManager.isBlocked(bundleID) { return nil }

            if self.skipNextWord {
                self.skipNextWord = false
                return nil
            }

            if self.exceptionsManager.contains(word) {
                return nil
            }

            return self.decideConversion(for: word)
        }

        // Perform the replacement. Returns true if replacement happened.
        keyboardMonitor.onReplace = { [weak self] original, replacement, boundary in
            guard let self, !self.isReplacing else { return false }
            self.isReplacing = true

            self.textReplacer.replace(
                characterCount: original.count,
                with: replacement + boundary
            )

            // Store for backspace-rejection tracking
            self.keyboardMonitor.lastConversion = (original: original, replacement: replacement)
            self.keyboardMonitor.lastConversionTime = ProcessInfo.processInfo.systemUptime
            let frontmostApp = NSWorkspace.shared.frontmostApplication
            self.keyboardMonitor.recordReplacement(
                original: original,
                replacement: replacement,
                boundary: boundary,
                appPID: frontmostApp?.processIdentifier ?? 0,
                appBundleID: frontmostApp?.bundleIdentifier ?? ""
            )

            // Switch keyboard layout to match the target language
            InputSourceSwitcher.switchToMatch(convertedText: replacement)
            self.statusBarController.syncLayoutBadge()

            // Toast with conversion text + screen flash
            let language: InputSourceSwitcher.Language = LayoutConverter.isCyrillic(replacement) ? .russian : .english
            self.layoutToastPresenter.show(language: language, conversion: (from: original, to: replacement))
            self.screenFlasher.flash(language: language)

            self.statusBarController.incrementStats()
            self.mlService.recordAccepted(word: original)

            // Phase 1: update session context with accepted conversion
            self.contextTracker.record(text: replacement)

            // Phase 1: record per-app conversion direction
            let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
            let toRussian = LayoutConverter.isCyrillic(replacement)
            self.appMemory.recordConversion(bundleID: bundleID, toRussian: toRussian)

            // Phase 2: label the pending sample and trigger retraining if ready
            self.sampleStore.labelLast(word: original, label: "convert")
            self.previousWord = replacement
            self.maybeRetrain()

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

            // Phase 1: per-app rejection
            let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
            self.appMemory.recordRejection(bundleID: bundleID)

            // Phase 2: label the sample as "skip"
            self.sampleStore.labelLast(word: word, label: "skip")
            self.maybeRetrain()

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
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyboardMonitor.isEnabled = false
        contextTracker.reset()
    }

    // MARK: - ML decision engine

    /// Core conversion decision. Tries Phase 3 predictor first; falls back to Phase 1.
    private func decideConversion(for word: String) -> String? {
        guard word.count <= settings.maxWordLength else { return nil }
        guard !LayoutConverter.isMixedScript(word), LayoutConverter.hasLetters(word) else { return nil }
        guard word.count != 1 || settings.singleLetterAutoConvert else { return nil }

        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        let isLatin = LayoutConverter.isLatin(word)

        let converted = LayoutConverter.convertPreservingCase(word)
        let isEN: Bool
        let isRU: Bool
        if isLatin {
            isEN = spellCheckService.isValidEnglish(word)
            isRU = spellCheckService.isValidRussian(converted)
        } else if LayoutConverter.isCyrillic(word) {
            isRU = spellCheckService.isValidRussian(word)
            isEN = spellCheckService.isValidEnglish(converted)
        } else {
            return nil
        }

        let sessionBoost = contextTracker.conversionBoost(wordIsLatin: isLatin)
        let appBias = appMemory.languageBias(for: bundleID)

        let originalValid = isLatin ? isEN : isRU
        let convertedValid = isLatin ? isRU : isEN
        let spellScore: Double
        if originalValid { spellScore = 0.0 }
        else if convertedValid { spellScore = 1.0 }
        else { spellScore = 0.6 }
        let combinedScore = spellScore * sessionBoost * (1.0 + appBias * 0.3)

        // Phase 2: record sample (label assigned later on accept/reject)
        let sample = ConversionSample(
            word: word.lowercased(),
            prevWord: previousWord,
            appBundleID: bundleID,
            sessionRuConf: contextTracker.russianConfidence,
            sessionEnConf: contextTracker.englishConfidence,
            appBias: appBias,
            spellValidEn: isEN,
            spellValidRu: isRU,
            wasLatin: isLatin,
            combinedScore: combinedScore,
            timestamp: Date().timeIntervalSince1970,
            label: nil
        )
        sampleStore.record(sample)

        // Phase 3: use CoreML predictor when confident
        if let predictor = coreMLPredictor,
           let prediction = predictor.predict(
               sessionRuConf: contextTracker.russianConfidence,
               sessionEnConf: contextTracker.englishConfidence,
               appBias: appBias,
               spellEn: isEN,
               spellRu: isRU,
               wasLatin: isLatin
           ), prediction.confidence > 0.7 {
            return prediction.label == "convert" ? converted : nil
        }

        // Phase 1: spell check + session context + per-app bias
        return spellCheckService.suggestConversion(
            for: word,
            exceptions: exceptionsManager.exceptions,
            sessionBoost: sessionBoost,
            appBias: appBias,
            threshold: settings.conversionThreshold
        )
    }

    private func maybeRetrain() {
        trainer.trainIfReady(samples: sampleStore.labeledSamples)
    }

    private func postModelStatus(_ status: String) {
        NotificationCenter.default.post(
            name: .switcherLMModelStatusChanged,
            object: nil,
            userInfo: ["status": status]
        )
    }

    // MARK: - Force conversion (Double-LShift)

    private func handleForceConvert() {
        getSelectedTextAsync { [weak self] selectedText in
            guard let self else { return }
            if let text = selectedText, !text.isEmpty {
                self.forceConvertSelection(text)
                return
            }
            guard let word = self.keyboardMonitor.takeCurrentWord(), !word.isEmpty else { return }
            let converted = LayoutConverter.convertPreservingCase(word)
            guard converted != word else { return }
            self.isReplacing = true
            self.textReplacer.replace(characterCount: word.count, with: converted)
            InputSourceSwitcher.switchToMatch(convertedText: converted)
            self.statusBarController.syncLayoutBadge()
            self.statusBarController.incrementStats()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.isReplacing = false
            }
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
        statusBarController.syncLayoutBadge()
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

    private func getSelectedTextAsync(completion: @escaping (String?) -> Void) {
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)
        let oldChangeCount = pasteboard.changeCount

        textReplacer.sendCopy()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard pasteboard.changeCount != oldChangeCount else {
                completion(nil)
                return
            }
            let text = pasteboard.string(forType: .string)
            pasteboard.clearContents()
            if let old = oldContents {
                pasteboard.setString(old, forType: .string)
            }
            completion(text)
        }
    }

    // MARK: - Undo last replacement

    private func handleUndoReplacement() {
        guard keyboardMonitor.hasPendingUndo else { return }
        guard let last = keyboardMonitor.lastReplacement else { return }

        isReplacing = true
        textReplacer.replace(
            characterCount: last.replacement.count + last.boundary.count,
            with: last.original + last.boundary
        )
        // Switch layout back to match the original text
        InputSourceSwitcher.switchToMatch(convertedText: last.original)
        statusBarController.syncLayoutBadge()
        keyboardMonitor.clearLastReplacement()

        // Treat undo as an explicit rejection so the ML pipeline learns from it
        sampleStore.labelLast(word: last.original, label: "skip")
        mlService.recordRejection(word: last.original)
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        appMemory.recordRejection(bundleID: bundleID)
        statusBarController.incrementRejections()
        maybeRetrain()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isReplacing = false
        }
    }

    // MARK: - Windows

    private func showExceptionsWindow() {
        if exceptionsWindowController == nil {
            exceptionsWindowController = ExceptionsWindowController(manager: exceptionsManager)
        }
        exceptionsWindowController?.showWindow()
    }

    private func showAppFilterWindow() {
        if appFilterWindowController == nil {
            appFilterWindowController = AppFilterWindowController(manager: appFilterManager)
        }
        appFilterWindowController?.showWindow()
    }

    private func showSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showWindow()
    }

    // MARK: - Secure field detection

    private func isFocusedOnSecureField() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            "AXFocusedUIElement" as CFString,
            &focusedRef
        ) == .success, let ref = focusedRef else { return false }
        guard CFGetTypeID(ref) == AXUIElementGetTypeID() else { return false }
        let element = ref as! AXUIElement
        var subroleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, "AXSubrole" as CFString, &subroleRef)
        return (subroleRef as? String) == "AXSecureTextField"
    }
}

extension Notification.Name {
    static let switcherLMModelStatusChanged = Notification.Name("SwitcherLM.ModelStatusChanged")
}
