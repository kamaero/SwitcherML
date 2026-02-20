import XCTest
@testable import SwitcherLM

final class SettingsStatsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "SwitcherLM_AutoConvertEnabled")
        UserDefaults.standard.removeObject(forKey: "SwitcherLM_DoubleShiftEnabled")
        UserDefaults.standard.removeObject(forKey: "SwitcherLM_SingleLetterAutoConvert")
        UserDefaults.standard.removeObject(forKey: "SwitcherLM_RejectionThreshold")
        UserDefaults.standard.removeObject(forKey: "SwitcherLM_MaxWordLength")
        UserDefaults.standard.removeObject(forKey: "SwitcherLM_SkipURLsAndEmail")
        UserDefaults.standard.removeObject(forKey: "SwitcherLM_ToastDuration")
        UserDefaults.standard.removeObject(forKey: "SwitcherLM_ToastCornerCount")
        UserDefaults.standard.removeObject(forKey: "SwitcherLM_TotalConverted")
        UserDefaults.standard.removeObject(forKey: "SwitcherLM_TotalRejected")
        UserDefaults.standard.removeObject(forKey: "SwitcherLM_DailyStats")
    }

    func testSettingsDefaults() {
        let settings = SettingsManager.shared
        XCTAssertTrue(settings.autoConvertEnabled)
        XCTAssertTrue(settings.doubleShiftEnabled)
        XCTAssertTrue(settings.singleLetterAutoConvert)
        XCTAssertEqual(settings.rejectionThreshold, 3)
        XCTAssertEqual(settings.maxWordLength, 40)
        XCTAssertTrue(settings.skipURLsAndEmail)
        XCTAssertEqual(settings.toastDuration, 0.55, accuracy: 0.001)
        XCTAssertEqual(settings.toastCornerCount, 4)
    }

    func testStatsPersistence() {
        let stats = StatsManager.shared
        stats.recordConverted()
        stats.recordRejected()

        XCTAssertEqual(stats.totalConverted, 1)
        XCTAssertEqual(stats.totalRejected, 1)
        XCTAssertEqual(stats.todayConverted, 1)
        XCTAssertEqual(stats.todayRejected, 1)
    }
}
