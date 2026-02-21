import Carbon
import Foundation

/// Switches the macOS keyboard input source (layout) programmatically.
struct InputSourceSwitcher {

    /// Known input source IDs
    static let englishSourceID = "com.apple.keylayout.ABC"
    static let russianSourceID = "com.apple.keylayout.Russian"

    /// Alternative IDs (some systems use these)
    private static let englishAlternatives = [
        "com.apple.keylayout.ABC",
        "com.apple.keylayout.US",
        "com.apple.keylayout.USInternational-PC",
    ]

    private static let russianAlternatives = [
        "com.apple.keylayout.Russian",
        "com.apple.keylayout.RussianWin",
        "com.apple.keylayout.Russian-Phonetic",
    ]

    struct InputSourceInfo {
        let id: String
        let name: String
    }

    /// Switch to English keyboard layout.
    static func switchToEnglish() {
        let preferred = SettingsManager.shared.preferredEnglishSourceID
        switchTo(preferred: preferred, candidates: englishAlternatives)
    }

    /// Switch to Russian keyboard layout.
    static func switchToRussian() {
        let preferred = SettingsManager.shared.preferredRussianSourceID
        switchTo(preferred: preferred, candidates: russianAlternatives)
    }

    /// Switch to the layout matching the target language of a conversion.
    /// If the converted text is Cyrillic → switch to Russian.
    /// If the converted text is Latin → switch to English.
    static func switchToMatch(convertedText: String) {
        if LayoutConverter.isCyrillic(convertedText) {
            switchToRussian()
        } else if LayoutConverter.isLatin(convertedText) {
            switchToEnglish()
        }
    }

    enum Language {
        case english
        case russian
        case unknown
    }

    /// Get current input source ID.
    static func currentSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
    }

    static func currentLanguage() -> Language {
        guard let id = currentSourceID() else { return .unknown }
        if englishAlternatives.contains(id) {
            return .english
        }
        if russianAlternatives.contains(id) {
            return .russian
        }
        return .unknown
    }

    /// List available keyboard input sources (id + localized name).
    static func availableInputSources() -> [InputSourceInfo] {
        guard let sources = TISCreateInputSourceList(nil, false)?
            .takeRetainedValue() as? [TISInputSource] else {
            return []
        }

        var result: [InputSourceInfo] = []
        for source in sources {
            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
                  let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName),
                  let typePtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceType) else {
                continue
            }
            let sourceID = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
            let name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
            let type = Unmanaged<CFString>.fromOpaque(typePtr).takeUnretainedValue() as String

            if type != (kTISTypeKeyboardLayout as String) && type != (kTISTypeKeyboardInputMode as String) {
                continue
            }

            result.append(InputSourceInfo(id: sourceID, name: name))
        }

        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Returns a short uppercase abbreviation for the current input source
    /// (e.g. "UK" for Ukrainian, "DE" for German). Falls back to "??".
    static func currentLayoutAbbreviation() -> String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else {
            return "??"
        }
        let name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
        let letters = name.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        let abbrev = String(letters.prefix(2)).uppercased()
        return abbrev.isEmpty ? "??" : abbrev
    }

    // MARK: - Private

    private static func switchTo(preferred: String?, candidates: [String]) {
        guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return
        }

        if let preferred {
            if let match = findSource(id: preferred, in: sources) {
                TISSelectInputSource(match)
                return
            }
        }

        for candidate in candidates {
            if let match = findSource(id: candidate, in: sources) {
                TISSelectInputSource(match)
                return
            }
        }

        print("InputSourceSwitcher: No matching input source found for preferred: \(preferred ?? "nil"), candidates: \(candidates)")
    }

    private static func findSource(id: String, in sources: [TISInputSource]) -> TISInputSource? {
        for source in sources {
            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
                continue
            }
            let sourceID = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
            if sourceID == id {
                return source
            }
        }
        return nil
    }
}
