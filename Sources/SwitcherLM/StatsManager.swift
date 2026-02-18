import Foundation

final class StatsManager {
    static let shared = StatsManager()

    private let defaults = UserDefaults.standard
    private let totalConvertedKey = "SwitcherLM_TotalConverted"
    private let totalRejectedKey = "SwitcherLM_TotalRejected"
    private let dailyStatsKey = "SwitcherLM_DailyStats"

    private struct DailyStat: Codable {
        var converted: Int
        var rejected: Int
    }

    private var dailyStats: [String: DailyStat] = [:]

    private init() {
        loadDailyStats()
    }

    var totalConverted: Int {
        defaults.integer(forKey: totalConvertedKey)
    }

    var totalRejected: Int {
        defaults.integer(forKey: totalRejectedKey)
    }

    var todayConverted: Int {
        dailyStats[dateKey(for: Date())]?.converted ?? 0
    }

    var todayRejected: Int {
        dailyStats[dateKey(for: Date())]?.rejected ?? 0
    }

    func recordConverted() {
        defaults.set(totalConverted + 1, forKey: totalConvertedKey)
        updateDaily(convertedDelta: 1, rejectedDelta: 0)
    }

    func recordRejected() {
        defaults.set(totalRejected + 1, forKey: totalRejectedKey)
        updateDaily(convertedDelta: 0, rejectedDelta: 1)
    }

    // MARK: - Daily stats

    private func updateDaily(convertedDelta: Int, rejectedDelta: Int) {
        let key = dateKey(for: Date())
        var stat = dailyStats[key] ?? DailyStat(converted: 0, rejected: 0)
        stat.converted += convertedDelta
        stat.rejected += rejectedDelta
        dailyStats[key] = stat
        saveDailyStats()
    }

    private func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func loadDailyStats() {
        guard let data = defaults.data(forKey: dailyStatsKey) else { return }
        if let decoded = try? JSONDecoder().decode([String: DailyStat].self, from: data) {
            dailyStats = decoded
        }
    }

    private func saveDailyStats() {
        if let data = try? JSONEncoder().encode(dailyStats) {
            defaults.set(data, forKey: dailyStatsKey)
        }
    }
}
