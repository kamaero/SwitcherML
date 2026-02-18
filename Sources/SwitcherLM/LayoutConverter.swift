import Foundation

/// Converts text between QWERTY (EN) and ЙЦУКЕН (RU) keyboard layouts.
struct LayoutConverter {

    // QWERTY → ЙЦУКЕН mapping (lowercase)
    private static let enToRu: [Character: Character] = [
        "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е",
        "y": "н", "u": "г", "i": "ш", "o": "щ", "p": "з",
        "[": "х", "]": "ъ", "a": "ф", "s": "ы", "d": "в",
        "f": "а", "g": "п", "h": "р", "j": "о", "k": "л",
        "l": "д", ";": "ж", "'": "э", "z": "я", "x": "ч",
        "c": "с", "v": "м", "b": "и", "n": "т", "m": "ь",
        ",": "б", ".": "ю", "/": ".", "`": "ё",
    ]

    // QWERTY → ЙЦУКЕН mapping (uppercase / shifted)
    private static let enToRuUpper: [Character: Character] = [
        "Q": "Й", "W": "Ц", "E": "У", "R": "К", "T": "Е",
        "Y": "Н", "U": "Г", "I": "Ш", "O": "Щ", "P": "З",
        "{": "Х", "}": "Ъ", "A": "Ф", "S": "Ы", "D": "В",
        "F": "А", "G": "П", "H": "Р", "J": "О", "K": "Л",
        "L": "Д", ":": "Ж", "\"": "Э", "Z": "Я", "X": "Ч",
        "C": "С", "V": "М", "B": "И", "N": "Т", "M": "Ь",
        "<": "Б", ">": "Ю", "?": ",", "~": "Ё",
    ]

    // Reverse mapping: ЙЦУКЕН → QWERTY
    private static let ruToEn: [Character: Character] = {
        var map = [Character: Character]()
        for (en, ru) in enToRu { map[ru] = en }
        return map
    }()

    private static let ruToEnUpper: [Character: Character] = {
        var map = [Character: Character]()
        for (en, ru) in enToRuUpper { map[ru] = en }
        return map
    }()

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

    /// Convert EN-typed text to RU.
    static func enToRussian(_ text: String) -> String {
        String(text.map { ch in
            enToRuUpper[ch] ?? enToRu[ch] ?? ch
        })
    }

    /// Convert RU-typed text to EN.
    static func ruToEnglish(_ text: String) -> String {
        String(text.map { ch in
            ruToEnUpper[ch] ?? ruToEn[ch] ?? ch
        })
    }

    /// Convert text to the opposite layout.
    static func convert(_ text: String) -> String {
        if isCyrillic(text) {
            return ruToEnglish(text)
        } else {
            return enToRussian(text)
        }
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
}

private extension String {
    func capitalizedFirstLetterOnly() -> String {
        guard let first = self.first else { return self }
        let head = String(first).uppercased()
        let tail = self.dropFirst().lowercased()
        return head + tail
    }
}
