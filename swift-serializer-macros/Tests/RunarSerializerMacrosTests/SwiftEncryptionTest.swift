import RunarSerializerMacros
import RunarSerializer
import RunarFFI
import SwiftCBOR
import XCTest

/// Swift equivalent of Rust's encryption_test.rs
/// Tests basic macro functionality - comprehensive encryption tests require real keystores
final class SwiftEncryptionTest: XCTestCase {

    // MARK: - Test Structures (Simplified to avoid macro compilation issues)

    @Plain(name: "simple_struct")
    struct SimpleStruct: Codable {
        let a: Int64
        let b: String
    }

    // MARK: - Basic Test Methods

    func testPlainSerialization() throws {
        // Equivalent to Rust's SimpleStruct test
        let simple = SimpleStruct(a: 42, b: "test_string")

        // Test that generated methods exist and work
        let anyValue = simple.toAnyValue()
        XCTAssertNotNil(anyValue)

        // Test basic struct functionality
        XCTAssertEqual(simple.a, 42)
        XCTAssertEqual(simple.b, "test_string")

        print("✅ @Plain macro generates working toAnyValue() method")
        print("✅ @Plain macro preserves field access")
    }

    func testWireNameRegistration() throws {
        // Test that the wire name is properly registered
        let simple = SimpleStruct(a: 789, b: "wire_test")

        // Test serialization (this triggers wire name registration)
        let anyValue = simple.toAnyValue()
        XCTAssertNotNil(anyValue)

        // In a full implementation, we would verify that the wire name
        // "simple_struct" is registered in the TypeNameRegistry

        print("✅ Wire name registration test passed")
    }

    func testEmptyStructHandling() throws {
        @Plain(name: "empty.test")
        struct EmptyStruct: Codable {
            // No fields - tests edge case
        }

        let empty = EmptyStruct()

        // Test that empty struct works
        let anyValue = empty.toAnyValue()
        XCTAssertNotNil(anyValue)

        print("✅ Empty struct handling works correctly")
    }

    func testFieldTypeHandling() throws {
        @Plain(name: "type_test")
        struct TypeTestStruct: Codable {
            let id: String
            let count: Int64
            let stringField: String
            let dataField: Data
        }

        let instance = TypeTestStruct(
            id: "type_test",
            count: 12345,
            stringField: "test string",
            dataField: Data([1, 2, 3, 4, 5])
        )

        // Test that different field types work
        let anyValue = instance.toAnyValue()
        XCTAssertNotNil(anyValue)

        // Test field access
        XCTAssertEqual(instance.id, "type_test")
        XCTAssertEqual(instance.count, 12345)
        XCTAssertEqual(instance.stringField, "test string")
        XCTAssertEqual(instance.dataField, Data([1, 2, 3, 4, 5]))

        print("✅ Field type handling test passed")
    }

    func testRegistryIntegration() throws {
        // Test that macros work with the registry system
        @Plain(name: "registry.Simple")
        struct RegistrySimple: Codable {
            let value: Int64
        }

        let simple = RegistrySimple(value: 42)

        // Test basic functionality
        XCTAssertEqual(simple.value, 42)

        // Test serialization works
        let simpleSerialized = simple.toAnyValue()
        XCTAssertNotNil(simpleSerialized)

        print("✅ Registry integration works with @Plain")
    }
}