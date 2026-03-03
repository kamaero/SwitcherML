import AppKit
import Carbon.HIToolbox

/// A button-style control that records a keyboard shortcut when clicked.
/// Shows current hotkey or "Click to set…" prompt. Includes a clear (×) button.
final class HotkeyRecorderField: NSView {

    /// Called when a new hotkey is recorded. keyCode is Carbon keycode; modifiers are NSEvent flags.
    var onHotkeyRecorded: ((Int, NSEvent.ModifierFlags) -> Void)?
    /// Called when the user clears the hotkey.
    var onCleared: (() -> Void)?

    private let displayButton: NSButton
    private let clearButton: NSButton
    private var isRecording = false

    // MARK: - Init

    override init(frame: NSRect) {
        displayButton = NSButton()
        clearButton = NSButton()
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        displayButton = NSButton()
        clearButton = NSButton()
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        displayButton.bezelStyle = .rounded
        displayButton.target = self
        displayButton.action = #selector(displayButtonClicked)
        displayButton.translatesAutoresizingMaskIntoConstraints = false

        clearButton.title = "✕"
        clearButton.bezelStyle = .rounded
        clearButton.target = self
        clearButton.action = #selector(clearButtonClicked)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.widthAnchor.constraint(equalToConstant: 28).isActive = true

        addSubview(displayButton)
        addSubview(clearButton)

        NSLayoutConstraint.activate([
            displayButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            displayButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            displayButton.widthAnchor.constraint(equalToConstant: 140),

            clearButton.leadingAnchor.constraint(equalTo: displayButton.trailingAnchor, constant: 6),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    // MARK: - Public API

    func configure(keyCode: Int, modifiers: NSEvent.ModifierFlags) {
        stopRecording()
        if keyCode < 0 {
            displayButton.title = "Выключен"
        } else {
            displayButton.title = HotkeyFormatter.string(keyCode: keyCode, modifiers: modifiers)
        }
    }

    // MARK: - Recording

    @objc private func displayButtonClicked() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    @objc private func clearButtonClicked() {
        stopRecording()
        displayButton.title = "Выключен"
        onCleared?()
    }

    private func startRecording() {
        isRecording = true
        displayButton.title = "Нажмите клавишу…"
        window?.makeFirstResponder(self)
    }

    private func stopRecording() {
        isRecording = false
        window?.makeFirstResponder(nil)
    }

    // MARK: - Key capture

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        let keyCode = Int(event.keyCode)

        // Escape cancels recording without changing the hotkey
        if keyCode == kVK_Escape {
            stopRecording()
            return
        }

        // Delete/Backspace clears the hotkey
        if keyCode == kVK_Delete || keyCode == kVK_ForwardDelete {
            clearButtonClicked()
            return
        }

        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        stopRecording()
        displayButton.title = HotkeyFormatter.string(keyCode: keyCode, modifiers: modifiers)
        onHotkeyRecorded?(keyCode, modifiers)
    }

    // Prevent system beep for unhandled keys while recording
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isRecording { return true }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - HotkeyFormatter

enum HotkeyFormatter {
    static func string(keyCode: Int, modifiers: NSEvent.ModifierFlags) -> String {
        var parts = ""
        if modifiers.contains(.control) { parts += "⌃" }
        if modifiers.contains(.option)  { parts += "⌥" }
        if modifiers.contains(.shift)   { parts += "⇧" }
        if modifiers.contains(.command) { parts += "⌘" }
        parts += keyName(for: keyCode)
        return parts
    }

    // swiftlint:disable:next cyclomatic_complexity
    static func keyName(for keyCode: Int) -> String {
        switch keyCode {
        case kVK_LeftArrow:       return "←"
        case kVK_RightArrow:      return "→"
        case kVK_UpArrow:         return "↑"
        case kVK_DownArrow:       return "↓"
        case kVK_Space:           return "Space"
        case kVK_Return:          return "↩"
        case kVK_Tab:             return "⇥"
        case kVK_Escape:          return "⎋"
        case kVK_Delete:          return "⌫"
        case kVK_ForwardDelete:   return "⌦"
        case kVK_Home:            return "↖"
        case kVK_End:             return "↘"
        case kVK_PageUp:          return "⇞"
        case kVK_PageDown:        return "⇟"
        case kVK_F1:              return "F1"
        case kVK_F2:              return "F2"
        case kVK_F3:              return "F3"
        case kVK_F4:              return "F4"
        case kVK_F5:              return "F5"
        case kVK_F6:              return "F6"
        case kVK_F7:              return "F7"
        case kVK_F8:              return "F8"
        case kVK_F9:              return "F9"
        case kVK_F10:             return "F10"
        case kVK_F11:             return "F11"
        case kVK_F12:             return "F12"
        default:
            // Map Carbon keycode → character via UCKeyTranslate
            if let ch = characterForKeyCode(keyCode) { return ch.uppercased() }
            return "Key\(keyCode)"
        }
    }

    private static func characterForKeyCode(_ keyCode: Int) -> String? {
        guard let keyboard = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(keyboard, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let dataRef = unsafeBitCast(layoutData, to: CFData.self)
        let keyboardLayout = unsafeBitCast(
            CFDataGetBytePtr(dataRef),
            to: UnsafePointer<UCKeyboardLayout>.self
        )
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let error = UCKeyTranslate(
            keyboardLayout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            4,
            &length,
            &chars
        )
        guard error == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}
