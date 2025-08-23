import RunarSerializerMacros
import XCTest

final class RunarMacroTests: XCTestCase {

    func testPlainMacroBasic() {
        // Test basic @Runar macro functionality
        @Runar
        struct SimpleStruct: Codable {
            let id: Int64
            let name: String
        }

        let simple = SimpleStruct(id: 42, name: "test")
        XCTAssertEqual(simple.id, 42)
        XCTAssertEqual(simple.name, "test")

        // Verify toAnyValue method exists and works
        let anyValue = simple.toAnyValue()
        XCTAssertNotNil(anyValue)
        XCTAssertEqual(anyValue.category(), .struct)
    }

    func testPlainMacroWithCustomName() {
        // Test @Runar(name: "...") syntax
        @Runar(name: "custom_struct")
        struct CustomStruct: Codable {
            let value: String
            let count: Int
        }

        let custom = CustomStruct(value: "hello", count: 10)
        XCTAssertEqual(custom.value, "hello")
        XCTAssertEqual(custom.count, 10)

        // Verify toAnyValue method exists
        let anyValue = custom.toAnyValue()
        XCTAssertNotNil(anyValue)
        XCTAssertEqual(anyValue.category(), .struct)
    }

    func testFieldLevelLabels() {
        // Test @Runar field-level labels
        @Encrypted
        struct TestStruct: Codable {
            let id: String
            @Runar("user") var userData: String
            @Runar("system") var systemData: String
            @Runar("user, system") var sharedData: String
            @Runar("search") var searchableData: String
        }

        let test = TestStruct(
            id: "123",
            userData: "user_secret",
            systemData: "system_info",
            sharedData: "shared_info",
            searchableData: "searchable"
        )

        // Verify all fields work
        XCTAssertEqual(test.id, "123")
        XCTAssertEqual(test.userData, "user_secret")
        XCTAssertEqual(test.systemData, "system_info")
        XCTAssertEqual(test.sharedData, "shared_info")
        XCTAssertEqual(test.searchableData, "searchable")
    }

    func testWireNameRegistration() {
        // Test that wire names are properly registered
        @Runar(name: "test.wire_name")
        struct WireTest: Codable {
            let data: String
        }

        let wire = WireTest(data: "test")
        XCTAssertEqual(wire.data, "test")

        // The bootstrap should register the wire name
        // This would be verified in integration tests with actual registry
        let anyValue = wire.toAnyValue()
        XCTAssertNotNil(anyValue)
    }

    func testComplexStruct() {
        // Test complex struct with various field types
        @Runar(name: "complex_test")
        struct ComplexStruct: Codable {
            let id: String
            let count: Int64
            let flag: Bool
            let values: [String]
            let metadata: [String: String]
        }

        let complex = ComplexStruct(
            id: "complex_123",
            count: 42,
            flag: true,
            values: ["a", "b", "c"],
            metadata: ["key1": "value1", "key2": "value2"]
        )

        // Verify all fields
        XCTAssertEqual(complex.id, "complex_123")
        XCTAssertEqual(complex.count, 42)
        XCTAssertEqual(complex.flag, true)
        XCTAssertEqual(complex.values, ["a", "b", "c"])
        XCTAssertEqual(complex.metadata["key1"], "value1")

        // Verify serialization method works
        let anyValue = complex.toAnyValue()
        XCTAssertNotNil(anyValue)
        XCTAssertEqual(anyValue.category(), .struct)
    }

    func testMultipleLabels() {
        // Test field with multiple labels
        @Encrypted(name: "multi_label_test")
        struct MultiLabelStruct: Codable {
            let id: String
            @Runar("user, system, search") var multiLabelData: String
            @Runar("system") var systemOnly: String
            @Runar("user") var userOnly: String
        }

        let multi = MultiLabelStruct(
            id: "multi_123",
            multiLabelData: "accessible_by_all",
            systemOnly: "system_data",
            userOnly: "user_data"
        )

        // Verify all fields
        XCTAssertEqual(multi.id, "multi_123")
        XCTAssertEqual(multi.multiLabelData, "accessible_by_all")
        XCTAssertEqual(multi.systemOnly, "system_data")
        XCTAssertEqual(multi.userOnly, "user_data")
    }
}
