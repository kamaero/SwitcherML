import AppKit
import Carbon.HIToolbox

final class SettingsManager: @unchecked Sendable {
    static let shared = SettingsManager()

    static let didChangeNotification = Notification.Name("SwitcherLM.SettingsChanged")

    private let defaults = UserDefaults.standard

    private enum Key {
        static let autoConvertEnabled = "SwitcherLM_AutoConvertEnabled"
        static let doubleShiftEnabled = "SwitcherLM_DoubleShiftEnabled"
        static let singleLetterAutoConvert = "SwitcherLM_SingleLetterAutoConvert"
        static let rejectionThreshold = "SwitcherLM_RejectionThreshold"
        static let maxWordLength = "SwitcherLM_MaxWordLength"
        static let skipURLsAndEmail = "SwitcherLM_SkipURLsAndEmail"
        static let toastDuration = "SwitcherLM_ToastDuration"
        static let toastCornerCount = "SwitcherLM_ToastCornerCount"
        static let preferredEnglishSourceID = "SwitcherLM_PreferredEnglishSourceID"
        static let preferredRussianSourceID = "SwitcherLM_PreferredRussianSourceID"
        static let conversionThreshold = "SwitcherLM_ConversionThreshold"
        static let screenFlashEnabled = "SwitcherLM_ScreenFlashEnabled"
        static let toastShowWords = "SwitcherLM_ToastShowWords"
        // Custom hotkey storage (replaces old UndoHotkey enum)
        static let undoKeyCode = "SwitcherLM_UndoKeyCode2"
        static let undoModifiers = "SwitcherLM_UndoModifiers2"
        // Legacy key (read-once for migration)
        static let undoHotkeyLegacy = "SwitcherLM_UndoHotkey"
    }

    /// -1 means hotkey is disabled. Default: kVK_LeftArrow (123) with no modifiers.
    var undoKeyCode: Int {
        get {
            if defaults.object(forKey: Key.undoKeyCode) == nil {
                return migratedKeyCode()
            }
            return defaults.integer(forKey: Key.undoKeyCode)
        }
        set { defaults.set(newValue, forKey: Key.undoKeyCode); notify() }
    }

    var undoModifiers: UInt {
        get {
            if defaults.object(forKey: Key.undoKeyCode) == nil {
                return migratedModifiers()
            }
            return UInt(bitPattern: defaults.integer(forKey: Key.undoModifiers))
        }
        set { defaults.set(Int(bitPattern: newValue), forKey: Key.undoModifiers); notify() }
    }

    /// Migrate from old UndoHotkey enum string to keyCode/modifiers on first read.
    private func migratedKeyCode() -> Int {
        let legacy = defaults.string(forKey: Key.undoHotkeyLegacy) ?? "leftArrow"
        switch legacy {
        case "disabled": return -1
        case "cmdZ":     return kVK_ANSI_Z
        default:         return kVK_LeftArrow
        }
    }

    private func migratedModifiers() -> UInt {
        let legacy = defaults.string(forKey: Key.undoHotkeyLegacy) ?? "leftArrow"
        switch legacy {
        case "cmdZ": return NSEvent.ModifierFlags.command.rawValue
        default:     return 0
        }
    }

    var autoConvertEnabled: Bool {
        get { defaults.object(forKey: Key.autoConvertEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.autoConvertEnabled); notify() }
    }

    var doubleShiftEnabled: Bool {
        get { defaults.object(forKey: Key.doubleShiftEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.doubleShiftEnabled); notify() }
    }

    var singleLetterAutoConvert: Bool {
        get { defaults.object(forKey: Key.singleLetterAutoConvert) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.singleLetterAutoConvert); notify() }
    }

    var rejectionThreshold: Int {
        get { defaults.object(forKey: Key.rejectionThreshold) as? Int ?? 3 }
        set { defaults.set(max(1, newValue), forKey: Key.rejectionThreshold); notify() }
    }

    var maxWordLength: Int {
        get { defaults.object(forKey: Key.maxWordLength) as? Int ?? 40 }
        set { defaults.set(max(5, newValue), forKey: Key.maxWordLength); notify() }
    }

    var skipURLsAndEmail: Bool {
        get { defaults.object(forKey: Key.skipURLsAndEmail) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.skipURLsAndEmail); notify() }
    }

    var toastDuration: Double {
        get {
            let value = defaults.object(forKey: Key.toastDuration) as? Double ?? 0.55
            return min(max(value, 0.2), 3.0)
        }
        set {
            defaults.set(min(max(newValue, 0.2), 3.0), forKey: Key.toastDuration)
            notify()
        }
    }

    var toastCornerCount: Int {
        get {
            let value = defaults.object(forKey: Key.toastCornerCount) as? Int ?? 4
            if value == 1 || value == 2 || value == 4 { return value }
            return 4
        }
        set {
            let normalized = (newValue == 1 || newValue == 2 || newValue == 4) ? newValue : 4
            defaults.set(normalized, forKey: Key.toastCornerCount)
            notify()
        }
    }

    var preferredEnglishSourceID: String? {
        get { defaults.string(forKey: Key.preferredEnglishSourceID) }
        set {
            if let value = newValue {
                defaults.set(value, forKey: Key.preferredEnglishSourceID)
            } else {
                defaults.removeObject(forKey: Key.preferredEnglishSourceID)
            }
            notify()
        }
    }

    var preferredRussianSourceID: String? {
        get { defaults.string(forKey: Key.preferredRussianSourceID) }
        set {
            if let value = newValue {
                defaults.set(value, forKey: Key.preferredRussianSourceID)
            } else {
                defaults.removeObject(forKey: Key.preferredRussianSourceID)
            }
            notify()
        }
    }

    /// Conversion confidence threshold (0.1 = aggressive, 0.9 = conservative).
    var conversionThreshold: Double {
        get {
            let value = defaults.object(forKey: Key.conversionThreshold) as? Double ?? 0.5
            return min(max(value, 0.1), 0.9)
        }
        set {
            defaults.set(min(max(newValue, 0.1), 0.9), forKey: Key.conversionThreshold)
            notify()
        }
    }

    /// Full-screen color flash on auto-conversion.
    var screenFlashEnabled: Bool {
        get { defaults.object(forKey: Key.screenFlashEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.screenFlashEnabled); notify() }
    }

    /// Show "original → converted" text in the conversion toast.
    var toastShowWords: Bool {
        get { defaults.object(forKey: Key.toastShowWords) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.toastShowWords); notify() }
    }

    private func notify() {
        NotificationCenter.default.post(name: SettingsManager.didChangeNotification, object: nil)
    }
}
