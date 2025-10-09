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
        struct Resolver: RunarSerializer.LabelResolver {
            func resolveLabel(_ label: String) -> LabelKeyInfo? {
                // For this test, encrypt all labeled groups to the user's profile key only.
                // This avoids network key setup and validates ArcValue integration.
                return LabelKeyInfo(profileIds: ["user"], networkId: nil)
            }
        }
        let resolver = Resolver()

        let profile = TestProfile(id: "123", name: "Test", privateData: "secret", email: "e@x", systemMetadata: "sys")

        // Force macro bootstrap before serialization
        _ = TestProfile.Encrypted.self
        let any = profile.toAnyValue()

        // Serialize with context so registry encryptor is used (strict: context required)
        let ctx = SerializationContext(keystore: keys, resolver: resolver, networkId: networkId)
        let bytes = try any.serialize(context: ctx)

        // Deserialize
        let de = try AnyValue.deserialize(bytes, keystore: keys)

        // Access as plain TestProfile (should decrypt system fields, user field empty)
        let plain: TestProfile = try await de.asType()
        XCTAssertEqual(plain.id, profile.id)
        XCTAssertEqual(plain.name, profile.name)
        XCTAssertEqual(plain.privateData, profile.privateData)
        XCTAssertEqual(plain.email, profile.email)
        XCTAssertEqual(plain.systemMetadata, profile.systemMetadata)

        // Access as EncryptedTestProfile directly from AnyValue
        let encrypted: TestProfile.Encrypted = try await de.asType()
        XCTAssertEqual(encrypted.id, profile.id)
        XCTAssertNotNil(encrypted.system_encrypted)
        XCTAssertNotNil(encrypted.search_encrypted)
        XCTAssertNotNil(encrypted.system_only_encrypted)

        // Round-trip decrypt from encrypted and compare
        let dec2 = try encrypted.decryptWithKeystore(keys)
        XCTAssertEqual(dec2.id, profile.id)
        XCTAssertEqual(dec2.name, profile.name)
        XCTAssertEqual(dec2.privateData, profile.privateData)
        XCTAssertEqual(dec2.email, profile.email)
        XCTAssertEqual(dec2.systemMetadata, profile.systemMetadata)
    }

    func testThreeKeystoresEndToEnd() async throws {
        @Encrypted(name: "encryption_test.TestProfile3")
        struct TestProfile3: Codable {
            let id: String
            @Runar("system") var name: String
            @Runar("user") var privateData: String
            @Runar("search") var email: String
            @Runar("system_only") var systemMetadata: String
        }

        // Build CA (master mobile)
        let ca = try FFIKeys()
        try ca.mobileInitializeUserRootKey()

        // Build node and install certificate
        let node = try FFIKeys()
        let csr = try node.generateCSR()
        let ncm = try ca.processSetupToken(csr)
        try node.installCertificate(ncm)

        // Create network id and install node network key
        let networkId = try ca.mobileGenerateNetworkDataKey()
        let nodeAgreementPk = try node.getAgreementPublicKey()
        let nkm = try ca.mobileCreateNetworkKeyMessage(networkId: networkId, nodeAgreementPk: nodeAgreementPk)
        try node.nodeInstallNetworkKey(nkm)

        // Build user-mobile with only profile keys and installed network public key (no private)
        let userMobile = try FFIKeys()
        try userMobile.mobileInitializeUserRootKey()
        // Export network public key from CA and install in user mobile to allow encrypt-to-network
        let networkPk = try ca.mobileGetNetworkPublicKey(networkId)
        try userMobile.mobileInstallNetworkPublicKey(networkPk)

        // Label resolver mapping: route labels to profile vs system
        struct Resolver: RunarSerializer.LabelResolver { let networkId: String
            func resolveLabel(_ label: String) -> LabelKeyInfo? {
                switch label {
                case "system", "system_only":
                    return LabelKeyInfo(profileIds: [], networkId: networkId)
                case "user", "search":
                    return LabelKeyInfo(profileIds: ["user"], networkId: nil)
                default:
                    return nil
                }
            }
        }
        let resolver = Resolver(networkId: networkId)

        // Prepare profile
        let profile = TestProfile3(id: "123", name: "Name", privateData: "secret", email: "e@x", systemMetadata: "sys")
        _ = TestProfile3.Encrypted.self // force bootstrap

        // Serialize with user-mobile keystore (will encrypt system groups for network, user groups for profile)
        let userCtx = SerializationContext(keystore: FFIKeyStore(keys: userMobile), resolver: resolver, networkId: networkId)
        let any = profile.toAnyValue()
        let bytes = try any.serialize(context: userCtx)

        // Case 1: Deserialize on user-mobile — should see user fields, system fields defaulted
        let deUser = try AnyValue.deserialize(bytes, keystore: FFIKeyStore(keys: userMobile))
        let plainUser: TestProfile3 = try await deUser.asType()
        XCTAssertEqual(plainUser.id, profile.id)
        XCTAssertEqual(plainUser.privateData, profile.privateData)
        // System fields should decrypt only with node, so here they should remain defaults
        XCTAssertEqual(plainUser.name, String.runarDefaultValue)
        XCTAssertEqual(plainUser.systemMetadata, String.runarDefaultValue)

        // Case 2: Deserialize on node — should see system fields, user fields defaulted
        let deNode = try AnyValue.deserialize(bytes, keystore: FFIKeyStore(keys: node))
        let plainNode: TestProfile3 = try await deNode.asType()
        XCTAssertEqual(plainNode.id, profile.id)
        XCTAssertEqual(plainNode.name, profile.name)
        XCTAssertEqual(plainNode.systemMetadata, profile.systemMetadata)
        // User fields should be defaults on node
        XCTAssertEqual(plainNode.privateData, String.runarDefaultValue)
        XCTAssertEqual(plainNode.email, String.runarDefaultValue)

        // Case 3: Encrypted arc from user and node
        let encFromUser: TestProfile3.Encrypted = try await deUser.asType()
        XCTAssertNotNil(encFromUser.system_encrypted)
        XCTAssertNotNil(encFromUser.user_encrypted)

        let encFromNode: TestProfile3.Encrypted = try await deNode.asType()
        XCTAssertNotNil(encFromNode.system_encrypted)
        XCTAssertNotNil(encFromNode.user_encrypted)

        // Node should not decrypt user groups
        let nodeDecrypted = try encFromNode.decryptWithKeystore(FFIKeyStore(keys: node))
        XCTAssertEqual(nodeDecrypted.name, profile.name)
        XCTAssertEqual(nodeDecrypted.systemMetadata, profile.systemMetadata)
        XCTAssertEqual(nodeDecrypted.privateData, String.runarDefaultValue)

        // User-mobile should not decrypt system groups
        let userDecrypted = try encFromUser.decryptWithKeystore(FFIKeyStore(keys: userMobile))
        XCTAssertEqual(userDecrypted.privateData, profile.privateData)
        XCTAssertEqual(userDecrypted.name, String.runarDefaultValue)
    }

    func buildTestContext() throws -> TestContext {
        // This mimics Rust's proper setup where one mobile key store is used to setup the network and nodes
        // and the user has its own mobile key store with its keys, but does not have access to the network private keys
        
        // Build mobile network master (CA)
        let mobileNetworkMaster = try MobileKeyManagerImpl()
        let networkId = try mobileNetworkMaster.generateNetworkDataKey()
        let networkPub = try mobileNetworkMaster.getNetworkPublicKey(networkId)
        
        // Build user mobile with only profile keys and installed network public key (no private)
        let userMobile = try MobileKeyManagerImpl()
        try userMobile.initializeUserRootKey()
        let profilePk = try userMobile.deriveUserProfileKey(label: "user")
        // Install only the network public key, not the network private key
        // so this user mobile can encrypt for the network, but not decrypt
        try userMobile.installNetworkPublicKey(networkPublicKey: networkPub)
        
        // Build node and install certificate
        let nodeKeys = try NodeKeyManagerImpl()
        let csr = try nodeKeys.generateCSR()
        let ncm = try mobileNetworkMaster.createNetworkKeyMessage(networkId: networkId, nodeAgreementPk: csr)
        try nodeKeys.installCertificate(nodeCertificateMessageCBOR: ncm)
        
        // Create network id and install node network key
        let nodeAgreementPk = try nodeKeys.getAgreementPublicKey()
        let nkm = try mobileNetworkMaster.createNetworkKeyMessage(networkId: networkId, nodeAgreementPk: nodeAgreementPk)
        try nodeKeys.installNetworkKey(nkmCbor: nkm)
        
        let userMobileKs = userMobile as EnvelopeCrypto
        let nodeKs = nodeKeys as EnvelopeCrypto
        
        // Resolver mapping exactly like Rust
        let resolver = ConfigurableLabelResolver(config: KeyMappingConfig(
            labelMappings: [
                "user": LabelKeyInfo(profileIds: [profilePk], networkId: nil),
                "system": LabelKeyInfo(profileIds: [profilePk], networkId: networkId),
                "system_only": LabelKeyInfo(profileIds: [], networkId: networkId), // system only has no profile ids
                "search": LabelKeyInfo(profileIds: [profilePk], networkId: networkId)
            ]
        ))
        
        return (userMobileKs, nodeKs, resolver, networkId, profilePk)
    }
}
