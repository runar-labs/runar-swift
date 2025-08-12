import XCTest
@testable import SwiftCommon

final class NodeIdTests: XCTestCase {
    func testCompactIdNotEmpty() {
        let pub = Data(repeating: 0x42, count: 97)
        let id = NodeId.compactId(from: pub)
        XCTAssertFalse(id.isEmpty)
    }
}


