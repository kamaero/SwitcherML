import Foundation
import AppKit

/// Per-app EN/RU conversion statistics stored in `app_memory.json`.
struct AppLangStats: Codable {
    var ruConversions: Int = 0
    var enConversions: Int = 0
    var rejections: Int = 0
}

/// Remembers how often each app uses Russian vs English conversions and
/// provides a bias signal to adjust conversion sensitivity per-app.
final class AppLanguageMemory {

    private var stats: [String: AppLangStats] = [:]
    private let fileURL: URL
    private var pendingSave: DispatchWorkItem?

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("SwitcherLM", isDirectory: true)

        try? FileManager.default.createDirectory(
            at: appSupport,
            withIntermediateDirectories: true
        )
        self.fileURL = appSupport.appendingPathComponent("app_memory.json")
        loadData()
    }

    /// Returns a bias in the range [-1.0, +1.0].
    /// Positive = app tends to use Russian, negative = tends to use English.
    func languageBias(for bundleID: String) -> Double {
        guard let s = stats[bundleID] else { return 0.0 }
        let total = Double(s.ruConversions + s.enConversions + s.rejections)
        guard total > 0 else { return 0.0 }
        return Double(s.ruConversions - s.enConversions) / total
    }

    func recordConversion(bundleID: String, toRussian: Bool) {
        if toRussian {
            stats[bundleID, default: AppLangStats()].ruConversions += 1
        } else {
            stats[bundleID, default: AppLangStats()].enConversions += 1
        }
        scheduleSave()
    }

    func recordRejection(bundleID: String) {
        stats[bundleID, default: AppLangStats()].rejections += 1
        scheduleSave()
    }

    // MARK: - Persistence

    private func loadData() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            stats = try JSONDecoder().decode([String: AppLangStats].self, from: data)
        } catch {
            print("AppLanguageMemory: Failed to load: \(error)")
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.performSave() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    private func performSave() {
        do {
            let data = try JSONEncoder().encode(stats)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("AppLanguageMemory: Failed to save: \(error)")
        }
    }
}
