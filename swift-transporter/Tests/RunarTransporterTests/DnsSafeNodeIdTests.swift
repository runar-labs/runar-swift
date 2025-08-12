@testable import RunarTransporter
import XCTest

final class DnsSafeNodeIdTests: XCTestCase {
    func testConversionRules() {
        XCTAssertEqual(DnsSafeNodeId.convert("abc-DEF_123"), "abcxDEFy123")
        XCTAssertEqual(DnsSafeNodeId.convert("a.b:c"), "azbzc")
        XCTAssertEqual(DnsSafeNodeId.convert("A1_z-"), "A1yzx")
        XCTAssertEqual(DnsSafeNodeId.convert(""), "")
    }
}
