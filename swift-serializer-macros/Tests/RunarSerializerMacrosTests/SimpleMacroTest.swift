import RunarSerializerMacros
import XCTest

final class SimpleMacroTest: XCTestCase {
    func testTestMacroExpansion() {
        // Test that the TestMacro expands without error
        @Test
        struct SimpleUser {
            let name: String
        }

        let user = SimpleUser(name: "Test")
        XCTAssertEqual(user.name, "Test")

        // Verify the macro added the expected method
        let result = user.testFunction()
        print("TestMacro expansion test passed")
    }

    func testMacroCompilation() {
        // Test that all macros compile successfully
        @Encrypted(name: "test.Profile")
        struct TestProfile: Codable {
            let id: String
            @Runar("user") var name: String
            @Runar("system") var data: String
        }

        @Runar
        struct SimpleStruct: Codable {
            let value: Int64
            let text: String
        }

        // Verify basic functionality
        let profile = TestProfile(id: "123", name: "Test", data: "system")
        XCTAssertEqual(profile.id, "123")
        XCTAssertEqual(profile.name, "Test")

        let simple = SimpleStruct(value: 42, text: "hello")
        XCTAssertEqual(simple.value, 42)
        XCTAssertEqual(simple.text, "hello")

        print("All macro compilation tests passed")
    }
}
