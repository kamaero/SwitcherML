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

    /// Switch to English keyboard layout.
    static func switchToEnglish() {
        switchTo(candidates: englishAlternatives)
    }

    /// Switch to Russian keyboard layout.
    static func switchToRussian() {
        switchTo(candidates: russianAlternatives)
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

    // MARK: - Private

    private static func switchTo(candidates: [String]) {
        guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return
        }

        for candidate in candidates {
            for source in sources {
                guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
                    continue
                }
                let sourceID = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
                if sourceID == candidate {
                    TISSelectInputSource(source)
                    return
                }
            }
        }

        print("InputSourceSwitcher: No matching input source found for candidates: \(candidates)")
    }
}
