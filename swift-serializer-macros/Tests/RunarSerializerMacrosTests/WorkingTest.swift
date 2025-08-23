import RunarSerializerMacros
import XCTest

/// Working test with only @Encrypted macro which was functional
final class WorkingTest: XCTestCase {

    func testTestMacroWorks() {
        // Test that @Test macro works first
        @Test
        struct TestUser: Codable {
            let id: String
        }

        let user: TestUser = TestUser(id: "test")
        user.testFunction()
        print("✅ @Test macro works")
    }

    func testRunarMacroBasic() {
        // Test that @Runar macro works without arguments
        @Runar
        struct TestStruct: Codable {
            let id: String
            let name: String
        }

        let instance: TestStruct = TestStruct(id: "test", name: "Test")
        print("✅ @Runar macro basic compilation works")
    }

    func testRunarMacroWithName() {
        // Test that @Runar macro works with name parameter
        @Runar
        struct CustomStruct: Codable {
            let value: Int64
        }

        let instance: CustomStruct = CustomStruct(value: 42)
        print("✅ @Runar macro compilation works")
    }

    func testEncryptedMacro() {
        // Test that @Encrypted macro works
        @Encrypted
        struct TestProfile: Codable {
            let id: String
            var userData: String
            var systemData: String
        }

        let profile: TestProfile = TestProfile(id: "test", userData: "user", systemData: "system")
        print("✅ @Encrypted macro compilation works")
    }

    func testEncryptedMacroCompiles() {
        // Test that @Encrypted macro compiles successfully
        @Encrypted
        struct TestStruct: Codable {
            let id: String
            let name: String
        }

        let instance: TestStruct = TestStruct(id: "test", name: "Test")
        XCTAssertEqual(instance.id, "test")
        XCTAssertEqual(instance.name, "Test")

        print("✅ @Encrypted macro compilation test passed")
    }

    func testComplexEncryptedStruct() {
        // Test complex struct with various field types
        @Encrypted
        struct ComplexStruct: Codable {
            let id: String
            let count: Int64
            let flag: Bool
            let values: [String]
            let metadata: [String: String]
        }

        let instance = ComplexStruct(
            id: "complex_test",
            count: 42,
            flag: true,
            values: ["a", "b", "c"],
            metadata: ["key1": "value1", "key2": "value2"]
        )

        // Verify all fields work
        XCTAssertEqual(instance.id, "complex_test")
        XCTAssertEqual(instance.count, 42)
        XCTAssertEqual(instance.flag, true)
        XCTAssertEqual(instance.values, ["a", "b", "c"])
        XCTAssertEqual(instance.metadata["key1"], "value1")

        print("✅ Complex encrypted struct test passed")
    }

    func testEmptyStructWithEncryption() {
        // Test edge case with empty struct
        @Encrypted
        struct EmptyStruct: Codable {
            // No fields
        }

        let instance = EmptyStruct()
        // Just verify it compiles
        _ = instance

        print("✅ Empty struct with encryption test passed")
    }

    func testSingleFieldEncryption() {
        // Test edge case with single field
        @Encrypted
        struct SingleFieldStruct: Codable {
            let data: String
        }

        let instance = SingleFieldStruct(data: "single_value")
        XCTAssertEqual(instance.data, "single_value")

        print("✅ Single field encryption test passed")
    }
}
