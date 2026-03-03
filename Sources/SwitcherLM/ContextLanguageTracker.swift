import Foundation
import NaturalLanguage

/// Tracks the language of recently accepted words to provide contextual
/// conversion hints. Maintains a rolling ~400-char buffer processed by
/// Apple's NLLanguageRecognizer neural model.
final class ContextLanguageTracker {

    private var buffer: [String] = []
    private var bufferLength: Int = 0
    private let maxBufferLength = 400

    private(set) var russianConfidence: Double = 0.0
    private(set) var englishConfidence: Double = 0.0

    /// Record a word that was typed and accepted (not converted away).
    func record(text: String) {
        guard !text.isEmpty else { return }
        buffer.append(text)
        bufferLength += text.count + 1 // +1 for implicit space

        // Trim oldest entries when buffer is over limit
        while bufferLength > maxBufferLength, !buffer.isEmpty {
            let removed = buffer.removeFirst()
            bufferLength -= removed.count + 1
        }

        updateConfidences()
    }

    /// Returns a multiplier for the conversion score based on surrounding
    /// language context.
    ///   > 1.0  — context suggests the mistyped script, convert more eagerly
    ///   < 1.0  — context suggests the current script, suppress conversion
    ///   = 1.0  — neutral / insufficient context
    func conversionBoost(wordIsLatin: Bool) -> Double {
        let signalStrength = russianConfidence + englishConfidence
        guard signalStrength > 0.1 else { return 1.0 }

        if wordIsLatin {
            // More Russian context → Latin word is likely a typo → boost
            let bias = (russianConfidence - englishConfidence) / signalStrength
            return 1.0 + bias * 0.5   // range 0.5 … 1.5
        } else {
            // More English context → Cyrillic word is likely a typo → boost
            let bias = (englishConfidence - russianConfidence) / signalStrength
            return 1.0 + bias * 0.5
        }
    }

    /// Call on session end to discard accumulated context.
    func reset() {
        buffer.removeAll()
        bufferLength = 0
        russianConfidence = 0.0
        englishConfidence = 0.0
    }

    // MARK: - Private

    private func updateConfidences() {
        guard !buffer.isEmpty else { return }
        let text = buffer.joined(separator: " ")
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 5)
        russianConfidence = hypotheses[.russian] ?? 0.0
        englishConfidence = hypotheses[.english] ?? 0.0
    }
}
