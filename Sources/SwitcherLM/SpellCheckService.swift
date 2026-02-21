import AppKit

/// Wraps NSSpellChecker for checking words in Russian and English.
final class SpellCheckService {

    private let checker = NSSpellChecker.shared
    private let settings = SettingsManager.shared
    private var cache: [String: Bool] = [:]
    private var cacheOrder: [String] = []
    private let cacheLimit = 500

    /// Check if a word is valid in the given language.
    /// - Parameters:
    ///   - word: The word to check.
    ///   - language: BCP-47 language tag, e.g. "en" or "ru".
    /// - Returns: `true` if the word is recognized by the spell checker.
    func isValid(word: String, language: String) -> Bool {
        let cacheKey = "\(language)|\(word)"
        if let cached = cache[cacheKey] {
            return cached
        }
        let range = checker.checkSpelling(
            of: word,
            startingAt: 0,
            language: language,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        // If range.location == NSNotFound, no misspelling was found → word is valid
        let isValid = range.location == NSNotFound
        cache[cacheKey] = isValid
        cacheOrder.append(cacheKey)
        if cacheOrder.count > cacheLimit {
            let oldest = cacheOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }
        return isValid
    }

    /// Check if a word is valid in English.
    func isValidEnglish(_ word: String) -> Bool {
        isValid(word: word, language: "en")
    }

    /// Check if a word is valid in Russian.
    func isValidRussian(_ word: String) -> Bool {
        isValid(word: word, language: "ru")
    }

    /// Score-aware overload: applies session context and per-app bias on top of
    /// the spell-check signal. `threshold` is typically `SettingsManager.shared.conversionThreshold`.
    ///
    ///   combinedScore = spellScore × sessionBoost × (1 + appBias × 0.3)
    ///   spellScore: 1.0 — spell check is confident; 0.6 — only one side valid; 0.0 — no signal
    func suggestConversion(
        for word: String,
        exceptions: Set<String>,
        sessionBoost: Double,
        appBias: Double,
        threshold: Double
    ) -> String? {
        let lowered = word.lowercased()
        if exceptions.contains(lowered) { return nil }
        if word.count == 1 { return singleLetterSuggestion(for: word) }
        if LayoutConverter.isMixedScript(word) || !LayoutConverter.hasLetters(word) { return nil }
        if word.count > settings.maxWordLength { return nil }
        if settings.skipURLsAndEmail && (Self.isLikelyURLOrPath(word) || Self.isLikelyEmail(word)) {
            return nil
        }

        let isLatin = LayoutConverter.isLatin(word)
        let converted = LayoutConverter.convertPreservingCase(word)

        let isEN: Bool
        let isRU: Bool
        if isLatin {
            isEN = isValidEnglish(word)
            isRU = isValidRussian(converted)
        } else if LayoutConverter.isCyrillic(word) {
            isRU = isValidRussian(word)
            isEN = isValidEnglish(converted)
        } else {
            return nil
        }

        // Compute spell-check confidence that conversion is the right call
        let spellScore: Double
        if isLatin || LayoutConverter.isCyrillic(word) {
            let originalValid = isLatin ? isEN : isRU
            let convertedValid = isLatin ? isRU : isEN
            if originalValid { spellScore = 0.0 }          // definitely correct script, don't convert
            else if convertedValid { spellScore = 1.0 }    // confident: original wrong, converted valid
            else { spellScore = 0.6 }                       // both invalid — weak signal
        } else {
            return nil
        }

        let combinedScore = spellScore * sessionBoost * (1.0 + appBias * 0.3)
        return combinedScore > threshold ? converted : nil
    }

    /// Determines whether a word needs layout switching.
    /// Returns the converted word if switching is recommended, nil otherwise.
    func suggestConversion(for word: String, exceptions: Set<String>) -> String? {
        let lowered = word.lowercased()

        // Skip exceptions
        if exceptions.contains(lowered) {
            return nil
        }

        // Single-letter smart conversion
        if word.count == 1 {
            return singleLetterSuggestion(for: word)
        }

        // Skip tokens with mixed scripts or no letters
        if LayoutConverter.isMixedScript(word) || !LayoutConverter.hasLetters(word) {
            return nil
        }

        // Skip very long tokens (likely IDs or pasted content)
        if word.count > settings.maxWordLength {
            return nil
        }

        // Skip URLs, emails, and file paths
        if settings.skipURLsAndEmail && (Self.isLikelyURLOrPath(word) || Self.isLikelyEmail(word)) {
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

    private func singleLetterSuggestion(for word: String) -> String? {
        if !settings.singleLetterAutoConvert {
            return nil
        }

        guard LayoutConverter.hasLetters(word) else { return nil }

        let lower = word.lowercased()

        if LayoutConverter.isLatin(word) {
            if lower == "a" || lower == "i" {
                return nil
            }
            let converted = LayoutConverter.convertPreservingCase(word)
            return LayoutConverter.isCyrillic(converted) ? converted : nil
        }

        if LayoutConverter.isCyrillic(word) {
            if lower == "а" || lower == "я" || lower == "и" {
                return nil
            }
            let converted = LayoutConverter.convertPreservingCase(word)
            let convertedLower = converted.lowercased()
            if convertedLower == "a" || convertedLower == "i" {
                return converted
            }
        }

        return nil
    }

    // MARK: - Heuristics

    static func isLikelyURLOrPath(_ word: String) -> Bool {
        let lower = word.lowercased()
        if lower.contains("://") || lower.hasPrefix("www.") {
            return true
        }
        if word.contains("/") || word.contains("\\") {
            return true
        }
        if lower.hasSuffix(".com") || lower.hasSuffix(".net") || lower.hasSuffix(".org") ||
           lower.hasSuffix(".ru") || lower.hasSuffix(".io") || lower.hasSuffix(".dev") {
            return true
        }
        return false
    }

    static func isLikelyEmail(_ word: String) -> Bool {
        guard let atIndex = word.firstIndex(of: "@") else { return false }
        let local = word[..<atIndex]
        let domain = word[word.index(after: atIndex)...]
        if local.isEmpty || domain.isEmpty {
            return false
        }
        return domain.contains(".")
    }
}
