import Foundation

/// Feature snapshot recorded at the moment a conversion decision is made.
/// The `label` field is filled in later via user feedback (accepted or rejected).
struct ConversionSample: Codable {
    let word: String
    let prevWord: String
    let appBundleID: String
    let sessionRuConf: Double
    let sessionEnConf: Double
    let appBias: Double
    let spellValidEn: Bool
    let spellValidRu: Bool
    let wasLatin: Bool
    let combinedScore: Double
    let timestamp: TimeInterval
    var label: String?   // "convert" | "skip"
}

/// Ring-buffer of ConversionSamples (max 5 000).
/// When full, oldest unlabeled samples are evicted first.
/// Persists to `~/Library/Application Support/SwitcherLM/samples.json`
/// with a 5-second debounced save.
final class SampleStore {

    private var samples: [ConversionSample] = []
    private let maxSamples = 5_000
    private let fileURL: URL
    private var pendingSave: DispatchWorkItem?

    /// Running count of samples that have received a label.
    private(set) var labeledCount: Int = 0

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("SwitcherLM", isDirectory: true)

        try? FileManager.default.createDirectory(
            at: appSupport,
            withIntermediateDirectories: true
        )
        self.fileURL = appSupport.appendingPathComponent("samples.json")
        loadData()
        labeledCount = samples.filter { $0.label != nil }.count
    }

    func record(_ sample: ConversionSample) {
        samples.append(sample)
        if samples.count > maxSamples {
            // Evict the oldest unlabeled sample first; fall back to oldest overall
            if let idx = samples.firstIndex(where: { $0.label == nil }) {
                samples.remove(at: idx)
            } else {
                samples.removeFirst()
            }
        }
    }

    /// Label the most recent unlabeled sample for `word`.
    func labelLast(word: String, label: String) {
        let key = word.lowercased()
        for i in stride(from: samples.count - 1, through: 0, by: -1) {
            if samples[i].word.lowercased() == key, samples[i].label == nil {
                samples[i].label = label
                labeledCount += 1
                scheduleSave()
                return
            }
        }
    }

    /// All samples that have been labeled by user feedback.
    var labeledSamples: [ConversionSample] {
        samples.filter { $0.label != nil }
    }

    var count: Int { samples.count }

    // MARK: - Persistence

    private func loadData() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            samples = try JSONDecoder().decode([ConversionSample].self, from: data)
        } catch {
            print("SampleStore: Failed to load: \(error)")
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.performSave() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: work)
    }

    private func performSave() {
        let snapshot = samples
        DispatchQueue.global(qos: .utility).async { [fileURL] in
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                print("SampleStore: Failed to save: \(error)")
            }
        }
    }
}
