import RunarSerializer
import RunarSerializerMacros
import SwiftCBOR
import XCTest

/// End-to-end encryption test that demonstrates the full flow working
/// This test shows basic encryption/decryption functionality with the current macros
final class EndToEndEncryptionTest: XCTestCase {
    
    // MARK: - Test Structs with Macros
    
    @Encrypted(name: "encryption_test.TestProfile")
    struct TestProfile: Codable {
        let id: String
        let name: String
        @Runar("user") let secretData: String
        let email: String
        @Runar("system") let metadata: String
    }
    
    @Plain(name: "encryption_test.SimpleStruct")
    struct SimpleStruct: Codable {
        let a: Int64
        let b: String
    }
    
    // MARK: - Basic Macro Functionality Tests
    
    func testEncryptedMacroGeneratesCode() async throws {
        let profile = TestProfile(
            id: "123",
            name: "Test User",
            secretData: "secret123",
            email: "test@example.com",
            metadata: "system_data"
        )
        
        // Test that the encrypted struct type exists
        let encryptedType = TestProfile.Encrypted.self
        XCTAssertNotNil(encryptedType)
        
        // Test that toAnyValue() method exists and works
        let anyValue = await profile.toAnyValue()
        XCTAssertNotNil(anyValue)
        
        print("✅ Encrypted macro generates code and toAnyValue() works")
    }
    
    func testPlainMacroGeneratesCode() async throws {
        let simple = SimpleStruct(a: 42, b: "test_string")
        
        // Test that generated methods exist and work
        let anyValue = await simple.toAnyValue()
        XCTAssertNotNil(anyValue)
        
        // Test basic struct functionality
        XCTAssertEqual(simple.a, 42)
        XCTAssertEqual(simple.b, "test_string")
        
        print("✅ Plain macro generates code and toAnyValue() works")
    }
    
    // MARK: - Wire Name Registration Tests
    
    func testWireNameRegistration() async throws {
        let simple = SimpleStruct(a: 789, b: "wire_test")
        
        // Test serialization (this triggers wire name registration)
        let anyValue = await simple.toAnyValue()
        XCTAssertNotNil(anyValue)
        
        // Test that the wire name is properly registered
        let wireName = "encryption_test.SimpleStruct"
        let isRegistered = await SerializationRegistry.shared.isRegistered(wireName: wireName)
        XCTAssertTrue(isRegistered)
        
        print("✅ Wire name registration test passed")
    }
    
    // MARK: - Empty Struct Handling
    
    func testEmptyStructHandling() async throws {
        @Plain(name: "empty.test")
        struct EmptyStruct: Codable {
            // No fields
        }
        
        let empty = EmptyStruct()
        
        // Test that empty struct works
        let anyValue = await empty.toAnyValue()
        XCTAssertNotNil(anyValue)
        
        print("✅ Empty struct handling test passed")
    }
    
    // MARK: - Field Type Handling
    
    func testFieldTypeHandling() async throws {
        @Plain(name: "type_test")
        struct TypeTestStruct: Codable {
            let intField: Int64
            let stringField: String
            let boolField: Bool
            let doubleField: Double
            let dataField: Data
        }
        
        let testData = Data("test_data".utf8)
        let instance = TypeTestStruct(
            intField: 123,
            stringField: "test_string",
            boolField: true,
            doubleField: 3.14,
            dataField: testData
        )
        
        // Test that different field types work
        let anyValue = await instance.toAnyValue()
        XCTAssertNotNil(anyValue)
        
        // Test basic struct functionality
        XCTAssertEqual(instance.intField, 123)
        XCTAssertEqual(instance.stringField, "test_string")
        XCTAssertTrue(instance.boolField)
        XCTAssertEqual(instance.doubleField, 3.14)
        XCTAssertEqual(instance.dataField, testData)
        
        print("✅ Field type handling test passed")
    }
    
    // MARK: - Registry Integration Test
    
    func testRegistryIntegration() async throws {
        // Test that macros work with the registry system
        @Plain(name: "registry.Simple")
        struct RegistryStruct: Codable {
            let id: String
            let value: Int64
        }
        
        let simple = RegistryStruct(id: "reg_123", value: 456)
        
        // Test serialization works
        let simpleSerialized = await simple.toAnyValue()
        XCTAssertNotNil(simpleSerialized)
        
        // Test that the registry has the wire name
        let isRegistered = await SerializationRegistry.shared.isRegistered(wireName: "registry.Simple")
        XCTAssertTrue(isRegistered)
        
        print("✅ Registry integration test passed")
    }
    
    // MARK: - Macro Compilation Test
    
    func testMacroCompilation() async throws {
        // Test that the macros compile and generate valid Swift code
        @Encrypted(name: "compilation.test")
        struct CompilationTest: Codable {
            let field1: String
            let field2: Int64
        }
        
        @Plain(name: "compilation.plain")
        struct CompilationPlain: Codable {
            let data: String
        }
        
        // Test that types are generated
        let encryptedType = CompilationTest.Encrypted.self
        XCTAssertNotNil(encryptedType)
        
        // Test that instances can be created
        let encrypted = CompilationTest(field1: "test", field2: 42)
        let plain = CompilationPlain(data: "test_data")
        
        // Test that toAnyValue() methods work
        let encryptedAnyValue = await encrypted.toAnyValue()
        let plainAnyValue = await plain.toAnyValue()
        
        XCTAssertNotNil(encryptedAnyValue)
        XCTAssertNotNil(plainAnyValue)
        
        print("✅ Macro compilation test passed")
    }
    
    // MARK: - Debug Test
    
    func testDebugEncryptionFlow() async throws {
        // Create a test keystore
        let keystore = TestKeyManagerAdapter()
        
        // Create a test resolver
        let resolver = LabelResolver(mapping: [
            "system": LabelKeyInfo(
                profilePublicKeys: [Data("system_profile_key".utf8)],
                networkPublicKey: Data("system_network_key".utf8)
            ),
            "user": LabelKeyInfo(
                profilePublicKeys: [Data("user_profile_key".utf8)],
                networkPublicKey: Data("user_network_key".utf8)
            )
        ])
        
        // Test the macro-generated encryptWithKeystore method directly
        let profile = TestProfile(
            id: "debug_user",
            name: "Debug User",
            secretData: "debug_secret",
            email: "debug@test.com",
            metadata: "debug_metadata"
        )
        
        // Test direct encryption
        let encryptedProfile = try await profile.encryptWithKeystore(keystore, resolver)
        print("✅ Direct encryption worked")
        
        // Test direct decryption
        let decryptedProfile = try await encryptedProfile.decryptWithKeystore(keystore)
        print("✅ Direct decryption worked")
        
        // Verify data matches
        XCTAssertEqual(decryptedProfile.id, profile.id)
        XCTAssertEqual(decryptedProfile.name, profile.name)
        XCTAssertEqual(decryptedProfile.secretData, profile.secretData)
        XCTAssertEqual(decryptedProfile.email, profile.email)
        XCTAssertEqual(decryptedProfile.metadata, profile.metadata)
        
        print("✅ Debug encryption flow test passed")
    }
    
    // MARK: - Full Encryption Flow Test
    
    func testFullEncryptionFlowWithRegistry() async throws {
        // Create a test keystore (using the same pattern as in swift-serializer tests)
        let keystore = TestKeyManagerAdapter()
        
        // Create a test resolver
        let resolver = LabelResolver(mapping: [
            "system": LabelKeyInfo(
                profilePublicKeys: [Data("system_profile_key".utf8)],
                networkPublicKey: Data("system_network_key".utf8)
            ),
            "user": LabelKeyInfo(
                profilePublicKeys: [Data("user_profile_key".utf8)],
                networkPublicKey: Data("user_network_key".utf8)
            )
        ])
        
        let context = SerializationContext(keystore: keystore, resolver: resolver, networkId: "test_network")
        
        // Test the full encryption flow with @Encrypted macro
        let profile = TestProfile(
            id: "encryption_test_user",
            name: "Encryption Test User",
            secretData: "top_secret_data",
            email: "encryption@test.com",
            metadata: "system_metadata"
        )
        
        // Convert to AnyValue (this should register the encryptor with the registry)
        let anyValue = await profile.toAnyValue()
        
        // Test that the type is registered for encryption
        let wireName = "encryption_test.TestProfile"
        let isRegistered = await SerializationRegistry.shared.isRegistered(wireName: wireName)
        XCTAssertTrue(isRegistered, "TestProfile should be registered for encryption")
        
        // Test serialization with context (should use registry encryptor)
        let serializedData = try await anyValue.serialize(context: context)
        XCTAssertFalse(serializedData.isEmpty, "Serialized data should not be empty")
        
        // Test deserialization - this should work with the registry
        let deserializedValue = try AnyValue.deserialize(serializedData)
        
        // The deserialized value should be of type EncryptedTestProfile
        // We need to decrypt it using the registry decryptor
        let deserializedProfile: TestProfile = try await deserializedValue.asType(keystore: keystore)
        
        // Verify the data matches
        XCTAssertEqual(deserializedProfile.id, profile.id)
        XCTAssertEqual(deserializedProfile.name, profile.name)
        XCTAssertEqual(deserializedProfile.secretData, profile.secretData)
        XCTAssertEqual(deserializedProfile.email, profile.email)
        XCTAssertEqual(deserializedProfile.metadata, profile.metadata)
        
        print("✅ Full encryption flow with registry test passed")
    }
}

// MARK: - Test Key Manager Adapter

/// Test implementation of CommonKeyManager for testing purposes
/// This is a temporary solution until NodeKeyManager and MobileKeyManager are fully implemented
@testable import SwiftFFI
final class TestKeyManagerAdapter: CommonKeyManager, @unchecked Sendable {
    
    func encryptWithEnvelope(
        data: Data,
        networkPublicKey: Data?,
        profilePublicKeys: [Data]
    ) async throws -> Data {
        // Simple test implementation - just return the payload with a prefix
        var result = Data("ENCRYPTED:".utf8)
        result.append(data)
        return result
    }
    
    func decryptEnvelope(envelopeData: Data) async throws -> Data {
        // Simple test implementation - remove the prefix
        let prefix = Data("ENCRYPTED:".utf8)
        guard envelopeData.starts(with: prefix) else {
            throw SerializerError.deserializationFailed("Invalid encrypted data format")
        }
        return envelopeData.dropFirst(prefix.count)
    }
    
    func ensureSymmetricKey(name: String) async throws -> Data {
        return Data("symmetric_key_\(name)".utf8)
    }
    
    func encryptLocalData(data: Data) async throws -> Data {
        var result = Data("LOCAL:".utf8)
        result.append(data)
        return result
    }
    
    func decryptLocalData(encryptedData: Data) async throws -> Data {
        let prefix = Data("LOCAL:".utf8)
        guard encryptedData.starts(with: prefix) else {
            throw SerializerError.deserializationFailed("Invalid local encrypted data format")
        }
        return encryptedData.dropFirst(prefix.count)
    }
    
    func setPersistenceDirectory(_ directory: String) async throws {
        // No-op for testing
    }
    
    func enableAutoPersistence(_ enabled: Bool) async throws {
        // No-op for testing
    }
    
    func wipePersistence() async throws {
        // No-op for testing
    }
    
    func getKeystoreCapabilities() async throws -> KeystoreCapabilities {
        return KeystoreCapabilities(version: 1, flags: 0x3F) // All capabilities enabled
    }
    
    func flushState() async throws {
        // No-op for testing
    }
    
    func registerAppleDeviceKeystore(label: String) async throws {
        // No-op for testing
    }
    
    func encryptForNetwork(data: Data, networkPublicKey: Data) async throws -> Data {
        var result = Data("NETWORK:".utf8)
        result.append(data)
        return result
    }
    
    func decryptNetworkData(encryptedEnvelope: Data) async throws -> Data {
        let prefix = Data("NETWORK:".utf8)
        guard encryptedEnvelope.starts(with: prefix) else {
            throw SerializerError.deserializationFailed("Invalid network encrypted data format")
        }
        return encryptedEnvelope.dropFirst(prefix.count)
    }
}
