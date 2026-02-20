import Foundation

final class SettingsManager {
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
        static let preferredEnglishSourceID = "SwitcherLM_PreferredEnglishSourceID"
        static let preferredRussianSourceID = "SwitcherLM_PreferredRussianSourceID"
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

    private func notify() {
        NotificationCenter.default.post(name: SettingsManager.didChangeNotification, object: nil)
    }
}
