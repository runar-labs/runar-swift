import RunarFFI
import RunarSerializer
import RunarSerializerMacros
import SwiftCBOR
import XCTest

final class BasicTest: XCTestCase {
    func testPlainMacroBasicStructure() {
        @Plain(name: "basic_test")
        struct BasicTest: Codable {
            let id: Int64
        }

        // Test that the struct compiles and has the expected structure
        let instance = BasicTest(id: 123)
        _ = instance

        print("✅ @Plain macro generates basic struct structure")
    }
}
