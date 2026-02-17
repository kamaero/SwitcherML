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

    /// Called when user backspaces away a recently converted word and retypes original.
    var onConversionRejected: ((String) -> Void)?

    private var currentWord: String = ""
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // -- Double LShift detection --
    private var lastLShiftUpTime: TimeInterval = 0
    private let doubleTapInterval: TimeInterval = 0.35

    // -- Backspace rejection tracking --
    /// The last conversion that happened: (original, replacement)
    var lastConversion: (original: String, replacement: String)?
    /// How many backspaces have been pressed since last conversion
    private var backspaceCountSinceConversion: Int = 0
    /// True if user is currently deleting the converted word
    private var isDeletingConversion: Bool = false

    // -- Last completed word (for force-convert) --
    private(set) var lastTypedWord: String = ""

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
        backspaceCountSinceConversion = 0
        isDeletingConversion = false
    }

    // MARK: - Event handling

    fileprivate func handleFlagsChanged(_ event: CGEvent) {
        guard isEnabled else { return }

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

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Backspace — track rejection of conversions
        if keyCode == Int64(kVK_Delete) {
            handleBackspace()
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
                if ch.isLetter || ch.isNumber {
                    currentWord.append(ch)
                } else {
                    // Punctuation/symbol acts as word boundary
                    let converted = processCurrentWord(boundary: String(ch))
                    if converted {
                        return nil // suppress — boundary included in paste
                    }
                }
            }
        }

        return event
    }

    // MARK: - Word processing

    /// Returns true if a conversion/replacement was performed.
    private func processCurrentWord(boundary: String) -> Bool {
        guard !currentWord.isEmpty else { return false }

        let word = currentWord
        currentWord = ""
        lastTypedWord = word

        // Check if this is the user retyping a word they rejected
        if let conv = lastConversion, word.lowercased() == conv.original.lowercased() {
            onConversionRejected?(conv.original)
            lastConversion = nil
            return false
        }

        if let replacement = shouldConvert?(word) {
            return onReplace?(word, replacement, boundary) ?? false
        }

        return false
    }

    // MARK: - Backspace tracking

    private func handleBackspace() {
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
