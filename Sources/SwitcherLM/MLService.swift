import Foundation

/// Learns from user behavior: tracks rejected conversions.
/// When a user backspaces a converted word and retypes the original N times,
/// the word is auto-added to exceptions.
final class MLService {

    /// Number of rejections needed before auto-adding to exceptions.
    private var rejectionThreshold: Int {
        SettingsManager.shared.rejectionThreshold
    }

    /// Tracks how many times each word's conversion was rejected.
    private var rejectionCounts: [String: Int] = [:]

    /// Total conversions performed and rejected (for stats).
    private(set) var totalConverted: Int = 0
    private(set) var totalRejected: Int = 0

    private let supportDir: URL
    private let rejectionDataURL: URL

    /// Called when a word reaches the rejection threshold.
    var onAutoException: ((String) -> Void)?

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("SwitcherLM", isDirectory: true)

        self.supportDir = appSupport
        self.rejectionDataURL = appSupport.appendingPathComponent("rejections.json")

        try? FileManager.default.createDirectory(
            at: appSupport,
            withIntermediateDirectories: true
        )

        loadData()
    }

    /// Record a successful conversion (user didn't undo it).
    func recordAccepted(word: String) {
        totalConverted += 1
    }

    /// Record a rejected conversion (user backspaced and retyped original).
    func recordRejection(word: String) {
        let key = word.lowercased()
        totalRejected += 1
        rejectionCounts[key, default: 0] += 1
        saveData()

        let count = rejectionCounts[key]!
        print("MLService: Rejection #\(count)/\(rejectionThreshold) for \"\(word)\"")

        if count >= rejectionThreshold {
            print("MLService: Auto-adding \"\(word)\" to exceptions (rejected \(count) times)")
            onAutoException?(key)
            rejectionCounts.removeValue(forKey: key)
            saveData()
        }
    }

    /// Get rejection count for a word.
    func rejectionCount(for word: String) -> Int {
        rejectionCounts[word.lowercased(), default: 0]
    }

    // MARK: - Persistence

    private func loadData() {
        guard FileManager.default.fileExists(atPath: rejectionDataURL.path) else { return }
        do {
            let data = try Data(contentsOf: rejectionDataURL)
            rejectionCounts = try JSONDecoder().decode([String: Int].self, from: data)
        } catch {
            print("MLService: Failed to load rejection data: \(error)")
        }
    }

    private func saveData() {
        do {
            let data = try JSONEncoder().encode(rejectionCounts)
            try data.write(to: rejectionDataURL, options: .atomic)
        } catch {
            print("MLService: Failed to save rejection data: \(error)")
        }
    }
}
