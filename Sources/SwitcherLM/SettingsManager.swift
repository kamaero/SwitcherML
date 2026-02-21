import Foundation

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
    /// Default 0.5 matches the pre-ML spell-check-only behaviour.
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

    private func notify() {
        NotificationCenter.default.post(name: SettingsManager.didChangeNotification, object: nil)
    }
}
