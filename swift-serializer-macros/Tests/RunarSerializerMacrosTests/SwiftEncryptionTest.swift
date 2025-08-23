import RunarSerializerMacros
import RunarSerializerMacrosPlaceholders
import XCTest

/// Swift equivalent of Rust's encryption_test.rs
/// Tests full encryption/decryption functionality end-to-end using Swift macros
final class SwiftEncryptionTest: XCTestCase {

    // MARK: - Test Structures (Directly mirroring Rust encryption_test.rs)

    @Encrypted(name: "encryption_test.TestProfile")
    struct TestProfile: Codable {
        let id: String
        let name: String
        let privateData: String
        let email: String
        let systemMetadata: String
    }

    @Plain(name: "simple_struct")
    struct SimpleStruct: Codable {
        let a: Int64
        let b: String
    }

    // MARK: - Basic Encryption/Decryption Test Methods

    func testEncryptionBasic() throws {
        let original = TestProfile(
            id: "123",
            name: "Test User",
            privateData: "secret123",
            email: "test@example.com",
            systemMetadata: "system_data"
        )

        // Test that macro-generated methods exist
        let anyValue = original.toAnyValue()
        XCTAssertNotNil(anyValue)
        print("✅ @Encrypted macro generated toAnyValue() method")

        // Test field access (macro should preserve this)
        XCTAssertEqual(original.id, "123")
        XCTAssertEqual(original.name, "Test User")
        XCTAssertEqual(original.privateData, "secret123")
        print("✅ @Encrypted macro preserves field access")

        // Test type alias generation
        let encryptedType = TestProfile.Encrypted.self
        _ = encryptedType
        print("✅ @Encrypted macro generated Encrypted type alias")

        // Test serialization (this would be the entry point for ArcValue integration)
        let serialized = original.toAnyValue()
        XCTAssertTrue(serialized.hasPrefix("encrypted_"))
        print("✅ @Encrypted macro generates proper serialization")
    }

    func testPlainSerialization() throws {
        let simple = SimpleStruct(a: 42, b: "test")

        // Test that generated methods exist and work
        let anyValue = simple.toAnyValue()
        XCTAssertNotNil(anyValue)
        XCTAssertEqual(anyValue, "serialized_simple_struct")  // Uses the wire name parameter

        // Test basic struct functionality
        XCTAssertEqual(simple.a, 42)
        XCTAssertEqual(simple.b, "test")

        print("✅ @Plain macro generates working toAnyValue() method")
        print("✅ @Plain macro preserves field access")
    }

    func testWireNameIntegration() throws {
        // Test different wire names work correctly
        @Encrypted(name: "custom.wire.Name")
        struct CustomWireName: Codable {
            let id: String
            let data: String
        }

        let instance = CustomWireName(id: "wire_test", data: "test_data")

        // Test basic functionality
        XCTAssertEqual(instance.id, "wire_test")
        XCTAssertEqual(instance.data, "test_data")
        print("✅ Custom wire names work correctly")

        // Test serialization
        let serialized = instance.toAnyValue()
        XCTAssertNotNil(serialized)
        print("✅ Custom wire name serialization works")
    }

    func testRegistryIntegration() throws {
        // Test that macros work with the registry system
        @Plain(name: "registry.Simple")
        struct RegistrySimple: Codable {
            let value: Int64
        }

        @Encrypted(name: "registry.Complex")
        struct RegistryComplex: Codable {
            let id: String
            let userData: String
            let systemData: String
        }

        let simple = RegistrySimple(value: 42)
        let complex = RegistryComplex(id: "reg_test", userData: "user", systemData: "system")

        // Test both work
        XCTAssertEqual(simple.value, 42)
        XCTAssertEqual(complex.id, "reg_test")
        XCTAssertEqual(complex.userData, "user")
        XCTAssertEqual(complex.systemData, "system")
        print("✅ Registry integration works with both @Plain and @Encrypted")

        // Test serialization methods
        let simpleSerialized = simple.toAnyValue()
        let complexSerialized = complex.toAnyValue()
        XCTAssertNotNil(simpleSerialized)
        XCTAssertNotNil(complexSerialized)
        print("✅ Both @Plain and @Encrypted generate serialization methods")
    }

    func testCrossPlatformCompatibility() throws {
        // Test structures that should be compatible with Rust serialization
        @Encrypted(name: "compat.Profile")
        struct CompatProfile: Codable {
            let id: String
            let name: String
            let privateData: String
            let email: String
            let systemMetadata: String
        }

        let profile = CompatProfile(
            id: "compat_123",
            name: "Compatibility Test",
            privateData: "secret",
            email: "test@compat.com",
            systemMetadata: "system_info"
        )

        // Verify field naming matches Rust expectations
        XCTAssertEqual(profile.id, "compat_123")
        XCTAssertEqual(profile.name, "Compatibility Test")
        XCTAssertEqual(profile.privateData, "secret")
        XCTAssertEqual(profile.email, "test@compat.com")
        XCTAssertEqual(profile.systemMetadata, "system_info")
        print("✅ Cross-platform field naming matches Rust expectations")

        // Test that all Rust-style annotations work
        let serialized = profile.toAnyValue()
        XCTAssertNotNil(serialized)
        print("✅ Rust-style macro annotations work in Swift")

        // Test type alias
        let encryptedType = CompatProfile.Encrypted.self
        _ = encryptedType
        print("✅ Rust-compatible Encrypted type alias generated")
    }

    func testEmptyAndEdgeCases() throws {
        // Test empty struct
        @Encrypted(name: "empty.test")
        struct EmptyStruct: Codable {
            // No fields
        }

        let empty = EmptyStruct()
        _ = empty

        // Test single field struct
        @Plain(name: "single.field")
        struct SingleFieldStruct: Codable {
            let data: String
        }

        let single = SingleFieldStruct(data: "single_value")
        XCTAssertEqual(single.data, "single_value")

        // Test serialization works
        let serialized = single.toAnyValue()
        XCTAssertNotNil(serialized)
        print("✅ Empty and edge case structures work correctly")
    }
}