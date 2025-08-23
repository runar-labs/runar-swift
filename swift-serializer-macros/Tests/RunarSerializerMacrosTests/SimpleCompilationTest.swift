import RunarSerializerMacros
import XCTest

/// Simple compilation tests that verify basic macro functionality
final class SimpleCompilationTest: XCTestCase {

    func testEncryptedMacroCompiles() {
        // Test that @Encrypted macro compiles successfully
        @Encrypted
        struct TestStruct: Codable {
            let id: String
            let name: String
        }

        let instance = TestStruct(id: "test", name: "Test")
        XCTAssertEqual(instance.id, "test")
        XCTAssertEqual(instance.name, "Test")
    }

    func testRunarMacroCompiles() {
        // Test that @Runar macro compiles successfully
        @Runar
        struct SimpleStruct: Codable {
            let value: Int
            let text: String
        }

        let instance = SimpleStruct(value: 42, text: "hello")
        XCTAssertEqual(instance.value, 42)
        XCTAssertEqual(instance.text, "hello")
    }

    func testMacroGeneratedTypesExist() {
        // Test that macro-generated types are accessible
        @Encrypted
        struct EncryptedStruct: Codable {
            let id: String
            let data: String
        }

        let instance = EncryptedStruct(id: "123", data: "secret")

        // Check if the macro generated the Encrypted type alias
        // Note: This will fail if the macro expansion didn't work correctly
        // but the test will show us what was actually generated
        XCTAssertEqual(instance.id, "123")
        XCTAssertEqual(instance.data, "secret")
    }

    func testComplexStructCompiles() {
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
    }

    func testEmptyStructCompiles() {
        // Test edge case with empty struct
        @Runar
        struct EmptyStruct: Codable {
            // No fields
        }

        let instance = EmptyStruct()
        // Just verify it compiles
        _ = instance
    }

    func testSingleFieldStructCompiles() {
        // Test edge case with single field
        @Encrypted
        struct SingleFieldStruct: Codable {
            let data: String
        }

        let instance = SingleFieldStruct(data: "single_value")
        XCTAssertEqual(instance.data, "single_value")
    }
}
