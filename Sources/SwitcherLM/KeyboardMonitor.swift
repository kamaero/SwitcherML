import AppKit
import Carbon.HIToolbox

/// Global keyboard event monitor. Buffers typed characters and triggers
/// layout-switch checks on word boundaries (space, enter, punctuation).
final class KeyboardMonitor {

    /// Called when a word should be replaced.
    /// Parameters: (original, replacement, boundaryCharacter).
    /// boundaryCharacter is the space/punctuation that triggered the check.
    /// Returns: true if replacement was performed.
    var onReplace: ((String, String, String) -> Bool)?

    /// Called to check if a word should be converted.
    var shouldConvert: ((String) -> String?)?

    /// Called on double-LShift to force-convert last word or selection.
    var onForceConvert: (() -> Void)?

    /// Called to undo the last replacement.
    var onUndoLastReplacement: (() -> Void)?

    /// Called to skip auto-conversion for the next word.
    var onSkipNextWord: (() -> Void)?

    /// Called when user backspaces away a recently converted word and retypes original.
    var onConversionRejected: ((String) -> Void)?

    private var currentWord: String = ""
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // -- Double LShift detection --
    private var lastLShiftUpTime: TimeInterval = 0
    private let doubleTapInterval: TimeInterval = 0.35
    private let settings = SettingsManager.shared

    // -- Backspace rejection tracking --
    /// The last conversion that happened: (original, replacement)
    var lastConversion: (original: String, replacement: String)?
    /// When the last conversion occurred (system uptime)
    var lastConversionTime: TimeInterval = 0
    /// Track the last replacement (for undo) and where it happened.
    var lastReplacement: (
        original: String,
        replacement: String,
        boundary: String,
        time: TimeInterval,
        appPID: pid_t,
        appBundleID: String
    )?
    /// True if user typed after the last replacement
    var hasTypedSinceReplacement: Bool = false
    /// Time window (seconds) to consider a rejection valid
    private let rejectionWindow: TimeInterval = 5.0
    /// How many backspaces have been pressed since last conversion
    private var backspaceCountSinceConversion: Int = 0
    /// True if user is currently deleting the converted word
    private var isDeletingConversion: Bool = false

    // -- Last completed word (for force-convert) --
    private(set) var lastTypedWord: String = ""

    /// True when there is a recent replacement eligible for undo.
    var hasPendingUndo: Bool {
        guard let last = lastReplacement, !hasTypedSinceReplacement else { return false }
        guard ProcessInfo.processInfo.systemUptime - last.time <= 5.0 else { return false }

        // Do not hijack undo in another app: only allow in the same frontmost app
        // where the auto-replacement happened.
        let frontmost = NSWorkspace.shared.frontmostApplication
        if let app = frontmost {
            if last.appPID != 0 && app.processIdentifier != last.appPID {
                return false
            }
            if !last.appBundleID.isEmpty,
               let bundleID = app.bundleIdentifier,
               bundleID != last.appBundleID {
                return false
            }
        }

        return true
    }

    // -- Context for single-letter conversion --
    private var lastEventWasBoundary: Bool = true
    private var wordStartWasBoundary: Bool = true
    private var isEditingExistingText: Bool = false

    var isEnabled: Bool = false {
        didSet {
            if isEnabled {
                start()
            } else {
                stop()
            }
        }
    }

    deinit {
        stop()
    }

    func start() {
        guard eventTap == nil else { return }

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: keyboardCallback,
            userInfo: userInfo
        ) else {
            print("KeyboardMonitor: Failed to create event tap. Check Accessibility permissions.")
            return
        }

        self.eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("KeyboardMonitor: Event tap started.")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        currentWord = ""
        print("KeyboardMonitor: Event tap stopped.")
    }

    /// Take the current in-progress word from the buffer (and clear it).
    /// Used by force-convert when the word hasn't been submitted yet.
    func takeCurrentWord() -> String? {
        guard !currentWord.isEmpty else { return nil }
        let word = currentWord
        currentWord = ""
        return word
    }

    func clearLastConversion() {
        lastConversion = nil
        lastConversionTime = 0
        backspaceCountSinceConversion = 0
        isDeletingConversion = false
    }

    func recordReplacement(
        original: String,
        replacement: String,
        boundary: String,
        appPID: pid_t,
        appBundleID: String
    ) {
        lastReplacement = (
            original: original,
            replacement: replacement,
            boundary: boundary,
            time: ProcessInfo.processInfo.systemUptime,
            appPID: appPID,
            appBundleID: appBundleID
        )
        hasTypedSinceReplacement = false
    }

    func clearLastReplacement() {
        lastReplacement = nil
        hasTypedSinceReplacement = false
    }

    // MARK: - Event handling

    fileprivate func handleFlagsChanged(_ event: CGEvent) {
        guard isEnabled else { return }

        if event.getIntegerValueField(.eventSourceUserData) == EventMarker.userData {
            return
        }

        if !settings.doubleShiftEnabled {
            return
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Left Shift keyCode is kVK_Shift (56)
        guard keyCode == Int64(kVK_Shift) else { return }

        // Detect key-up: shift flag is no longer set
        if !flags.contains(.maskShift) {
            let now = ProcessInfo.processInfo.systemUptime
            let elapsed = now - lastLShiftUpTime

            if elapsed < doubleTapInterval && elapsed > 0.05 {
                onForceConvert?()
                lastLShiftUpTime = 0
            } else {
                lastLShiftUpTime = now
            }
        }
    }

    /// Process a keyDown event. Returns nil to suppress the event, or the event to pass through.
    fileprivate func handleKeyEvent(_ event: CGEvent) -> CGEvent? {
        guard isEnabled else { return event }

        if event.getIntegerValueField(.eventSourceUserData) == EventMarker.userData {
            return event
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let modifiers = event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])

        // Backspace — track rejection of conversions
        if keyCode == Int64(kVK_Delete) {
            handleBackspace()
            return event
        }

        // Generic undo hotkey check — runs before navigation keys so any key can be assigned.
        if checkUndoHotkey(keyCode: keyCode, modifiers: modifiers) { return nil }

        if keyCode == Int64(kVK_LeftArrow) {
            isEditingExistingText = true
            lastEventWasBoundary = false
            return event
        }

        if keyCode == Int64(kVK_RightArrow) {
            onSkipNextWord?()
            isEditingExistingText = true
            lastEventWasBoundary = false
            return event
        }

        if keyCode == Int64(kVK_UpArrow) || keyCode == Int64(kVK_DownArrow) {
            isEditingExistingText = true
            lastEventWasBoundary = false
            return event
        }

        // Any non-backspace key resets the deletion tracking
        if isDeletingConversion {
            isDeletingConversion = false
        }

        // Word-boundary keys (space, enter, tab)
        if isWordBoundaryKeyCode(keyCode: keyCode) {
            let boundary = boundaryString(for: keyCode)
            let converted = processCurrentWord(boundary: boundary)
            lastEventWasBoundary = true
            // If conversion happened, suppress this event — boundary is included in paste
            return converted ? nil : event
        }

        // Get the character from the event
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(
            maxStringLength: 4,
            actualStringLength: &length,
            unicodeString: &chars
        )

        if length > 0 {
            let str = String(utf16CodeUnits: chars, count: length)
            for ch in str {
                if ch.isLetter || ch.isNumber || LayoutConverter.isConvertibleLetterKey(ch) {
                    if currentWord.isEmpty {
                        wordStartWasBoundary = lastEventWasBoundary && !isEditingExistingText
                        isEditingExistingText = false
                    }
                    currentWord.append(ch)
                    if lastReplacement != nil {
                        hasTypedSinceReplacement = true
                    }
                    lastEventWasBoundary = false
                } else if isJoiner(ch), !currentWord.isEmpty {
                    currentWord.append(ch)
                } else {
                    // Punctuation/symbol acts as word boundary
                    lastEventWasBoundary = true
                    let converted = processCurrentWord(boundary: String(ch))
                    if converted {
                        return nil // suppress — boundary included in paste
                    }
                }
            }
        }

        return event
    }

    // MARK: - Undo hotkey check

    /// Returns true and fires undo if the event matches the configured undo hotkey.
    private func checkUndoHotkey(keyCode: Int64, modifiers: CGEventFlags) -> Bool {
        let storedCode = settings.undoKeyCode
        guard storedCode >= 0, hasPendingUndo else { return false }
        guard keyCode == Int64(storedCode) else { return false }

        let storedMods = NSEvent.ModifierFlags(rawValue: settings.undoModifiers)
            .intersection([.command, .shift, .option, .control])
        // modifiers from CGEvent use mask* names — convert to NSEvent flags for comparison
        var eventMods = NSEvent.ModifierFlags()
        if modifiers.contains(.maskCommand)   { eventMods.insert(.command) }
        if modifiers.contains(.maskShift)     { eventMods.insert(.shift) }
        if modifiers.contains(.maskAlternate) { eventMods.insert(.option) }
        if modifiers.contains(.maskControl)   { eventMods.insert(.control) }

        guard eventMods == storedMods else { return false }
        onUndoLastReplacement?()
        return true
    }

    // MARK: - Word processing

    /// Returns true if a conversion/replacement was performed.
    private func processCurrentWord(boundary: String) -> Bool {
        guard !currentWord.isEmpty else { return false }

        let word = currentWord
        currentWord = ""
        lastTypedWord = word

        if word.count == 1 && !wordStartWasBoundary {
            return false
        }

        if lastConversionTime > 0 {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastConversionTime > rejectionWindow {
                clearLastConversion()
            }
        }

        // Check if this is the user retyping a word they rejected
        if let conv = lastConversion,
           isDeletingConversion,
           word.lowercased() == conv.original.lowercased() {
            onConversionRejected?(conv.original)
            clearLastConversion()
            return false
        }

        if let replacement = shouldConvert?(word) {
            return onReplace?(word, replacement, boundary) ?? false
        }

        return false
    }

    // MARK: - Backspace tracking

    private func handleBackspace() {
        if currentWord.isEmpty {
            isEditingExistingText = true
        }

        if lastConversionTime > 0 {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastConversionTime > rejectionWindow {
                clearLastConversion()
            }
        }

        if !currentWord.isEmpty {
            currentWord.removeLast()
            return
        }

        // No current word being typed — user is deleting previously submitted text
        if let conv = lastConversion {
            backspaceCountSinceConversion += 1
            if backspaceCountSinceConversion >= conv.replacement.count {
                isDeletingConversion = true
            }
        }
    }

    // MARK: - Helpers

    private func isWordBoundaryKeyCode(keyCode: Int64) -> Bool {
        let boundaries: Set<Int64> = [
            Int64(kVK_Space),
            Int64(kVK_Return),
            Int64(kVK_Tab),
        ]
        return boundaries.contains(keyCode)
    }

    private func boundaryString(for keyCode: Int64) -> String {
        switch keyCode {
        case Int64(kVK_Space):  return " "
        case Int64(kVK_Return): return "\n"
        case Int64(kVK_Tab):    return "\t"
        default:                return " "
        }
    }

    private func isJoiner(_ ch: Character) -> Bool {
        ch == "'" || ch == "-" || ch == "’"
    }
}

/// C-function callback for CGEvent tap.
private func keyboardCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let userInfo = userInfo {
            let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            if let tap = monitor.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passRetained(event)
    }

    guard let userInfo = userInfo else {
        return Unmanaged.passRetained(event)
    }

    let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .flagsChanged {
        monitor.handleFlagsChanged(event)
        return Unmanaged.passRetained(event)
    }

    guard type == .keyDown else {
        return Unmanaged.passRetained(event)
    }

    if let resultEvent = monitor.handleKeyEvent(event) {
        return Unmanaged.passRetained(resultEvent)
    }
    // nil means the event was consumed (suppressed)
    return nil
}
