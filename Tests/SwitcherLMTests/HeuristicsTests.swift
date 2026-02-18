import XCTest
@testable import SwitcherLM

final class HeuristicsTests: XCTestCase {

    func testMixedScriptDetection() {
        XCTAssertTrue(LayoutConverter.isMixedScript("HelloПривет"))
        XCTAssertFalse(LayoutConverter.isMixedScript("Hello"))
        XCTAssertFalse(LayoutConverter.isMixedScript("Привет"))
    }

    func testURLDetection() {
        XCTAssertTrue(SpellCheckService.isLikelyURLOrPath("https://example.com"))
        XCTAssertTrue(SpellCheckService.isLikelyURLOrPath("www.example.com"))
        XCTAssertTrue(SpellCheckService.isLikelyURLOrPath("/usr/local/bin"))
        XCTAssertTrue(SpellCheckService.isLikelyURLOrPath("C:\\Windows\\System32"))
        XCTAssertTrue(SpellCheckService.isLikelyURLOrPath("example.com"))
        XCTAssertFalse(SpellCheckService.isLikelyURLOrPath("example"))
    }

    func testEmailDetection() {
        XCTAssertTrue(SpellCheckService.isLikelyEmail("test@example.com"))
        XCTAssertFalse(SpellCheckService.isLikelyEmail("test@"))
        XCTAssertFalse(SpellCheckService.isLikelyEmail("@example.com"))
        XCTAssertFalse(SpellCheckService.isLikelyEmail("test@example"))
    }
}
