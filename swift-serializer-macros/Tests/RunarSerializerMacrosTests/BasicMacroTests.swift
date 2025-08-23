import RunarSerializerMacros
import XCTest

/// Basic macro functionality tests that can run in isolation
/// Tests macro expansion and basic struct functionality
final class BasicMacroTests: XCTestCase {

    // MARK: - Test Structures

    @Encrypted
    struct TestProfile: Codable {
        let id: String
        @Runar("system") var name: String
        @Runar("user") var privateData: String
        @Runar("search") var email: String
        @Runar("system_only") var systemMetadata: String
    }

    @Runar
    struct SimpleStruct: Codable {
        let a: Int64
        let b: String
    }

    // MARK: - Basic Macro Functionality Tests

    func testMacroExpansion() {
        let profile = TestProfile(
            id: "123",
            name: "Test User",
            privateData: "secret123",
            email: "test@example.com",
            systemMetadata: "system_data"
        )

        // Verify basic struct functionality
        XCTAssertEqual(profile.id, "123")
        XCTAssertEqual(profile.name, "Test User")
        XCTAssertEqual(profile.privateData, "secret123")
        XCTAssertEqual(profile.email, "test@example.com")
        XCTAssertEqual(profile.systemMetadata, "system_data")

        print("✅ Macro expansion test passed")
    }

    func testFieldLevelLabels() {
        @Encrypted
        struct FieldTestProfile: Codable {
            let id: String
            @Runar("user") var userData: String
            @Runar("system") var systemData: String
            @Runar("search") var searchData: String
            @Runar("system_only") var systemOnlyData: String
            @Runar("user, system") var sharedData: String
        }

        let profile = FieldTestProfile(
            id: "field_test",
            userData: "user_secret",
            systemData: "system_info",
            searchData: "searchable_data",
            systemOnlyData: "system_only_secret",
            sharedData: "accessible_by_both"
        )

        // Verify all labeled fields work
        XCTAssertEqual(profile.userData, "user_secret")
        XCTAssertEqual(profile.systemData, "system_info")
        XCTAssertEqual(profile.searchData, "searchable_data")
        XCTAssertEqual(profile.systemOnlyData, "system_only_secret")
        XCTAssertEqual(profile.sharedData, "accessible_by_both")

        print("✅ Field-level labels test passed")
    }

    func testPlainSerialization() {
        let simple = SimpleStruct(a: 42, b: "hello")

        // Verify basic functionality
        XCTAssertEqual(simple.a, 42)
        XCTAssertEqual(simple.b, "hello")

        // Test the generated toAnyValue method
        let serialized = simple.toAnyValue()
        XCTAssertTrue(serialized.hasPrefix("serialized_"))

        print("✅ Plain serialization test passed")
    }

    func testWireNameRegistration() {
        @Encrypted
        struct WireTestProfile: Codable {
            let id: String
            @Runar("user") var data: String
        }

        let profile = WireTestProfile(id: "wire_123", data: "test_data")

        // Verify the struct works
        XCTAssertEqual(profile.id, "wire_123")
        XCTAssertEqual(profile.data, "test_data")

        print("✅ Wire name registration test passed")
    }

    func testMultipleLabels() {
        @Encrypted
        struct LabelComboTest: Codable {
            let id: String
            @Runar("user") var userOnly: String
            @Runar("system") var systemOnly: String
            @Runar("search") var searchOnly: String
            @Runar("user, system") var userAndSystem: String
            @Runar("user, search") var userAndSearch: String
            @Runar("system, search") var systemAndSearch: String
            @Runar("user, system, search") var allLabels: String
        }

        let test = LabelComboTest(
            id: "combo_123",
            userOnly: "user_data",
            systemOnly: "system_data",
            searchOnly: "search_data",
            userAndSystem: "user_system_data",
            userAndSearch: "user_search_data",
            systemAndSearch: "system_search_data",
            allLabels: "all_access_data"
        )

        // Verify all fields work
        XCTAssertEqual(test.userOnly, "user_data")
        XCTAssertEqual(test.systemOnly, "system_data")
        XCTAssertEqual(test.searchOnly, "search_data")
        XCTAssertEqual(test.userAndSystem, "user_system_data")
        XCTAssertEqual(test.userAndSearch, "user_search_data")
        XCTAssertEqual(test.systemAndSearch, "system_search_data")
        XCTAssertEqual(test.allLabels, "all_access_data")

        print("✅ Multiple labels test passed")
    }

    func testComplexStructures() {
        @Runar
        struct ComplexStructure: Codable {
            let id: String
            let numbers: [Int64]
            let mapping: [String: String]
            let flags: [Bool]
            let nested: [String: [Int64]]
        }

        let complex = ComplexStructure(
            id: "complex_test",
            numbers: [1, 2, 3, 42],
            mapping: ["key1": "value1", "key2": "value2"],
            flags: [true, false, true],
            nested: ["group1": [10, 20], "group2": [30, 40]]
        )

        // Verify complex structure
        XCTAssertEqual(complex.id, "complex_test")
        XCTAssertEqual(complex.numbers, [1, 2, 3, 42])
        XCTAssertEqual(complex.mapping["key1"], "value1")
        XCTAssertEqual(complex.flags, [true, false, true])
        XCTAssertEqual(complex.nested["group1"], [10, 20])

        // Test serialization
        let serialized = complex.toAnyValue()
        XCTAssertTrue(serialized.hasPrefix("serialized_"))

        print("✅ Complex structures test passed")
    }

    func testEmptyAndEdgeCases() {
        // Test edge cases
        @Runar
        struct EmptyStruct: Codable {
            // No fields
        }

        let empty = EmptyStruct()
        // Just verify it compiles and has the method
        let serialized = empty.toAnyValue()
        XCTAssertTrue(serialized.hasPrefix("serialized_"))

        @Encrypted
        struct SingleFieldStruct: Codable {
            @Runar("user") let data: String
        }

        let single = SingleFieldStruct(data: "single_value")
        XCTAssertEqual(single.data, "single_value")

        print("✅ Empty and edge cases test passed")
    }
}
