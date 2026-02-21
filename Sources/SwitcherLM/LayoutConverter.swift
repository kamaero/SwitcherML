import Foundation

/// Converts text between configured keyboard layouts.
struct LayoutConverter {

    private static let config = LayoutConfigLoader.load()
    private static let activePair = config.activePair
    private static let mapLeftToRight = config.leftToRightMap
    private static let mapRightToLeft = config.rightToLeftMap

    private static func scriptStats(_ text: String) -> (latin: Int, cyrillic: Int, letters: Int) {
        var latin = 0
        var cyrillic = 0
        var letters = 0
        for scalar in text.unicodeScalars {
            if ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) {
                latin += 1
                letters += 1
            } else if ("а"..."я").contains(scalar) || ("А"..."Я").contains(scalar) || scalar == "ё" || scalar == "Ё" {
                cyrillic += 1
                letters += 1
            }
        }
        return (latin, cyrillic, letters)
    }

    /// Detects whether the string is predominantly Cyrillic.
    static func isCyrillic(_ text: String) -> Bool {
        let stats = scriptStats(text)
        return stats.cyrillic > stats.letters / 2
    }

    /// Detects whether the string is predominantly Latin.
    static func isLatin(_ text: String) -> Bool {
        let stats = scriptStats(text)
        return stats.latin > stats.letters / 2
    }

    /// Returns true when the text contains both Latin and Cyrillic letters.
    static func isMixedScript(_ text: String) -> Bool {
        let stats = scriptStats(text)
        return stats.latin > 0 && stats.cyrillic > 0
    }

    /// Returns true when the text contains at least one letter.
    static func hasLetters(_ text: String) -> Bool {
        let stats = scriptStats(text)
        return stats.letters > 0
    }

    /// Returns true when a key maps to a letter in either direction.
    static func isConvertibleLetterKey(_ ch: Character) -> Bool {
        if let mapped = mapLeftToRight[ch], mapped.isLetter {
            return true
        }
        if let mapped = mapRightToLeft[ch], mapped.isLetter {
            return true
        }
        return false
    }

    /// Convert EN-typed text to RU.
    static func enToRussian(_ text: String) -> String {
        convert(text, using: mapLeftToRight)
    }

    /// Convert RU-typed text to EN.
    static func ruToEnglish(_ text: String) -> String {
        convert(text, using: mapRightToLeft)
    }

    /// Convert text to the opposite layout.
    static func convert(_ text: String) -> String {
        if isCyrillic(text) {
            return convert(text, using: mapRightToLeft)
        }
        return convert(text, using: mapLeftToRight)
    }

    /// Convert preserving the original capitalization pattern.
    static func convertPreservingCase(_ text: String) -> String {
        let converted = convert(text)
        let originalLetters = text.filter { $0.isLetter }
        let convertedLetters = converted.filter { $0.isLetter }

        guard !originalLetters.isEmpty, originalLetters.count == convertedLetters.count else {
            return converted
        }

        if originalLetters.allSatisfy({ $0.isUppercase }) {
            return converted.uppercased()
        }

        if originalLetters.allSatisfy({ $0.isLowercase }) {
            return converted.lowercased()
        }

        if isTitleCase(originalLetters) {
            return converted.capitalizedFirstLetterOnly()
        }

        return applyPerCharacterCase(from: text, to: converted)
    }

    private static func isTitleCase(_ letters: String) -> Bool {
        guard let first = letters.first else { return false }
        if !first.isUppercase { return false }
        return letters.dropFirst().allSatisfy { $0.isLowercase }
    }

    private static func applyPerCharacterCase(from original: String, to converted: String) -> String {
        let originalChars = Array(original)
        let convertedChars = Array(converted)
        guard originalChars.count == convertedChars.count else { return converted }

        var result: [Character] = []
        result.reserveCapacity(convertedChars.count)

        for idx in 0..<convertedChars.count {
            let o = originalChars[idx]
            let c = convertedChars[idx]
            if o.isLetter {
                if o.isUppercase {
                    result.append(c.uppercased().first ?? c)
                } else {
                    result.append(c.lowercased().first ?? c)
                }
            } else {
                result.append(c)
            }
        }

        return String(result)
    }

    private static func convert(_ text: String, using map: [Character: Character]) -> String {
        String(text.map { ch in
            map[ch] ?? ch
        })
    }
}

private extension String {
    func capitalizedFirstLetterOnly() -> String {
        guard let first = self.first else { return self }
        let head = String(first).uppercased()
        let tail = self.dropFirst().lowercased()
        return head + tail
    }
}
