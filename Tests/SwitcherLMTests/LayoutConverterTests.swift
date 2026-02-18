import XCTest
@testable import SwitcherLM

final class LayoutConverterTests: XCTestCase {

    func testBasicConversionEnToRu() {
        XCTAssertEqual(LayoutConverter.enToRussian("ghbdtn"), "привет")
        XCTAssertEqual(LayoutConverter.enToRussian("Hello"), "Руддщ")
    }

    func testBasicConversionRuToEn() {
        XCTAssertEqual(LayoutConverter.ruToEnglish("руддщ"), "hello")
        XCTAssertEqual(LayoutConverter.ruToEnglish("Привет"), "Ghbdtn")
    }

    func testCasePreservationAllCaps() {
        XCTAssertEqual(LayoutConverter.convertPreservingCase("GHBDTN"), "ПРИВЕТ")
    }

    func testCasePreservationTitle() {
        XCTAssertEqual(LayoutConverter.convertPreservingCase("Ghbdtn"), "Привет")
    }

    func testCasePreservationMixed() {
        XCTAssertEqual(LayoutConverter.convertPreservingCase("gHbDtN"), "пРиВеТ")
    }
}
