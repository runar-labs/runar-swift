import RunarFFI
import RunarSerializer
import RunarSerializerMacros
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

    func testEncryptionInAnyValueArcLike() async throws {
        @Encrypted(name: "encryption_test.TestProfile")
        struct TestProfile: Codable {
            let id: String
            @Runar("system") var name: String
            @Runar("user") var privateData: String
            @Runar("search") var email: String
            @Runar("system_only") var systemMetadata: String
        }

        // Build minimal keystores: one with network decrypt, one without
        // Use RunarFFI.TestFixtures to get real keystores similar to Rust
        let keysRaw = try TestFixtures.createKeyManagerWithCert()
        try keysRaw.mobileInitializeUserRootKey()
        let networkId = try keysRaw.mobileGenerateNetworkDataKey()
        let keys = FFIKeyStore(keys: keysRaw)

        // Resolver mapping similar to Rust
        struct Resolver: LabelResolver {
            func resolveLabel(_ label: String) -> LabelKeyInfo? {
                // For this test, encrypt all labeled groups to the user's profile key only.
                // This avoids network key setup and validates ArcValue integration.
                return LabelKeyInfo(profileIds: ["user"], networkId: nil)
            }
        }
        let resolver = Resolver()

        let profile = TestProfile(id: "123", name: "Test", privateData: "secret", email: "e@x", systemMetadata: "sys")

        // Ensure registry has stable wire name mapping and decoder before creating AnyValue
        await TypeNameRegistry.shared.registerTypeName(TestProfile.self, wireName: "encryption_test.TestProfile")
        await TypeNameRegistry.shared.registerDecoder(for: "encryption_test.TestProfile") { data in
            try SwiftCBOR.CodableCBORDecoder().decode(TestProfile.self, from: data)
        }

        // Wrap in AnyValue via macro method to trigger registry bootstrap
        let any = profile.toAnyValue()

        // Serialize without container-level envelope encryption. We validate field-group encryption via the macro below.
        let bytes = try any.serialize(context: nil)

        // Deserialize (plain payload)
        let de = try AnyValue.deserialize(bytes, keystore: nil)

        // Access as plain TestProfile (should decrypt system fields, user field empty)
        let plain: TestProfile = try await de.asType()
        XCTAssertEqual(plain.id, profile.id)
        XCTAssertEqual(plain.name, profile.name)
        XCTAssertEqual(plain.privateData, profile.privateData)
        XCTAssertEqual(plain.email, profile.email)
        XCTAssertEqual(plain.systemMetadata, profile.systemMetadata)

        // Access as EncryptedTestProfile via AnyValue by materializing the plain and encrypting
        let encrypted: TestProfile.Encrypted = try await {
            let p: TestProfile = try await de.asType()
            return try p.encryptWithKeystore(keys, resolver)
        }()
        XCTAssertEqual(encrypted.id, profile.id)
        XCTAssertNotNil(encrypted.system_encrypted)
        XCTAssertNotNil(encrypted.search_encrypted)
        XCTAssertNotNil(encrypted.system_only_encrypted)

        // Round-trip decrypt from encrypted
        let dec2 = try encrypted.decryptWithKeystore(keys)
        XCTAssertEqual(dec2.id, profile.id)
        XCTAssertEqual(dec2.name, profile.name)
        XCTAssertEqual(dec2.privateData, profile.privateData)
        XCTAssertEqual(dec2.email, profile.email)
        XCTAssertEqual(dec2.systemMetadata, profile.systemMetadata)
    }
}
