import AppKit

/// Wraps NSSpellChecker for checking words in Russian and English.
final class SpellCheckService {

    private let checker = NSSpellChecker.shared

    /// Check if a word is valid in the given language.
    /// - Parameters:
    ///   - word: The word to check.
    ///   - language: BCP-47 language tag, e.g. "en" or "ru".
    /// - Returns: `true` if the word is recognized by the spell checker.
    func isValid(word: String, language: String) -> Bool {
        let range = checker.checkSpelling(
            of: word,
            startingAt: 0,
            language: language,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        // If range.location == NSNotFound, no misspelling was found → word is valid
        return range.location == NSNotFound
    }

    /// Check if a word is valid in English.
    func isValidEnglish(_ word: String) -> Bool {
        isValid(word: word, language: "en")
    }

    /// Check if a word is valid in Russian.
    func isValidRussian(_ word: String) -> Bool {
        isValid(word: word, language: "ru")
    }

    /// Determines whether a word needs layout switching.
    /// Returns the converted word if switching is recommended, nil otherwise.
    func suggestConversion(for word: String, exceptions: Set<String>) -> String? {
        let lowered = word.lowercased()

        // Skip exceptions
        if exceptions.contains(lowered) {
            return nil
        }

        // Single-char words are too ambiguous for auto-conversion (e.g. I↔Ш)
        // Use double-LShift to force-convert these manually
        if word.count < 2 {
            return nil
        }

        if LayoutConverter.isLatin(word) {
            // Word looks Latin — check English spelling
            if isValidEnglish(word) {
                return nil // Valid English word, no switch needed
            }
            // Try converting to Russian
            let converted = LayoutConverter.convertPreservingCase(word)
            if isValidRussian(converted) {
                return converted
            }
        } else if LayoutConverter.isCyrillic(word) {
            // Word looks Cyrillic — check Russian spelling
            if isValidRussian(word) {
                return nil // Valid Russian word, no switch needed
            }
            // Try converting to English
            let converted = LayoutConverter.convertPreservingCase(word)
            if isValidEnglish(converted) {
                return converted
            }
        }

        return nil
    }
}
