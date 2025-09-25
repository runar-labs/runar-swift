import XCTest
import SwiftFFI
import SwiftCBOR
import RunarSerializer
import RunarSerializerMacros
import SwiftCommon

// Test struct with encryption - exactly matching Rust TestProfile
@Encrypted(name: "encryption_test.TestProfile")
struct TestProfile: Codable {
    let id: String
    @Runar("system") let name: String
    @Runar("user") let `private`: String
    @Runar("search") let email: String
    @Runar("system_only") let system_metadata: String
}

// Simple struct for basic serialization test - exactly matching Rust SimpleStruct
struct SimpleStruct: Codable {
    let a: Int64
    let b: String
}

// Test context type - exactly matching Rust TestContext
typealias TestContext = (
    mobileKeystore: MobileKeyManager,
    nodeKeystore: NodeKeyManager,
    resolver: LabelResolver,
    networkId: String,
    profilePk: Data
)

final class RustParityEncryptionTest: XCTestCase {
    
    // Swift logger for trace-level logging
    private let logger = RunarLogger(
        component: .serializer,
        config: LoggingConfig(level: .trace),
        nodeId: "test-node"
    )
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Set up logging for both Rust FFI layer and Swift layer
        logger.info("Setting up logging for Rust parity test")
        
        // Set Rust FFI logger to trace level
        try await FFILogger.setLogLevel(.trace)
        logger.info("Rust FFI logger set to trace level")
        
        // Set Swift logger node ID for context
        try await FFILogger.setLoggerNodeId("test-node")
        logger.info("Rust FFI logger node ID set to test-node")
        
        logger.info("Logging setup complete - both Rust and Swift layers at trace level")
    }
    
    // Build keystores + resolver for testing - exactly matching Rust build_test_context()
    func buildTestContext() async throws -> TestContext {
        logger.info("Building test context - exactly matching Rust build_test_context()")
        
        // This mimics a proper setup, where one mobile key store is used to setup the network and nodes
        // and the user has its own mobile key store with its keys, but does not have access to the network private keys
        
        logger.trace("Creating mobile network master keystore")
        let mobileNetworkMaster = try await MobileKeyManager()
        logger.trace("Generating network data key")
        let networkPub = try await mobileNetworkMaster.generateNetworkDataKey()
        logger.trace("Getting network ID from public key")
        let networkId = try await mobileNetworkMaster.getCompactId(for: networkPub)
        logger.debug("Network ID: \(networkId)")
        
        logger.trace("Creating user mobile keystore")
        let userMobile = try await MobileKeyManager()
        logger.trace("Initializing user root key")
        try await userMobile.initializeUserRootKey()
        logger.trace("Deriving user profile key for label 'user'")
        let profilePk = try await userMobile.deriveUserProfileKey(label: "user")
        logger.debug("Profile public key derived: \(profilePk.count) bytes")
        
        // Install only the network public key, not the network private key
        // so this user mobile can encrypt for the network, but not decrypt
        logger.trace("Installing network public key on user mobile")
        try await userMobile.installNetworkPublicKey(networkPub)
        
        logger.trace("Creating node keystore")
        let nodeKeys = try await NodeKeyManager()
        logger.trace("Generating node keys")
        try await nodeKeys.generateKeys()
        
        // Install network key on node using real agreement public key
        logger.trace("Getting node agreement public key")
        let nodeAgreementPublicKey = try await nodeKeys.getNodeAgreementPublicKey()
        logger.debug("Node agreement public key: \(nodeAgreementPublicKey.count) bytes")
        
        logger.trace("Creating network key message")
        let nkMsg = try await mobileNetworkMaster.createNetworkKeyMessage(
            networkPublicKey: networkPub,
            nodeAgreementPublicKey: nodeAgreementPublicKey
        )
        logger.debug("Network key message created: \(nkMsg.count) bytes")
        
        logger.trace("Installing network key on node")
        try await nodeKeys.installNetworkKey(nkMsg)
        logger.info("Node network key installation complete")
        
        logger.trace("Creating label resolver with mappings")
        let resolver = LabelResolver(mapping: [
            "user": LabelKeyInfo(
                profilePublicKeys: [profilePk],
                networkPublicKey: nil
            ),
            "system": LabelKeyInfo(
                profilePublicKeys: [profilePk],
                networkPublicKey: networkPub
            ),
            "system_only": LabelKeyInfo(
                profilePublicKeys: [], // system only has no profile ids
                networkPublicKey: networkPub
            ),
            "search": LabelKeyInfo(
                profilePublicKeys: [profilePk],
                networkPublicKey: networkPub
            )
        ])
        logger.info("Label resolver created with 4 label mappings")
        
        logger.info("Test context build complete - returning keystores and resolver")
        return (userMobile, nodeKeys, resolver, networkId, profilePk)
    }
    
    func testEncryptionBasic() async throws {
        logger.info("Starting testEncryptionBasic - exactly matching Rust test_encryption_basic")
        let (mobileKs, nodeKs, resolver, _, _) = try await buildTestContext()
        
        logger.trace("Creating test profile with sample data")
        let original = TestProfile(
            id: "123",
            name: "Test User",
            private: "secret123",
            email: "test@example.com",
            system_metadata: "system_data"
        )
        logger.debug("Test profile created: id=\(original.id), name=\(original.name)")
        
        // Test encryption
        logger.trace("Encrypting test profile with mobile keystore")
        let encrypted: TestProfile.EncryptedTestProfile = try await original.encryptWithKeystore(mobileKs, resolver)
        logger.info("Profile encryption successful")
        
        // Verify encrypted struct has the expected fields
        XCTAssertEqual(encrypted.id, "123")
        XCTAssertNotNil(encrypted.user_encrypted)
        XCTAssertNotNil(encrypted.system_encrypted)
        XCTAssertNotNil(encrypted.search_encrypted)
        XCTAssertNotNil(encrypted.system_only_encrypted)
        
        // Test decryption with mobile (should have access to user fields but not system_only)
        logger.trace("Testing decryption with mobile keystore")
        let decryptedMobile = try await encrypted.decryptWithKeystore(mobileKs)
        logger.debug("Mobile decryption successful - verifying access control")
        XCTAssertEqual(decryptedMobile.id, original.id)
        XCTAssertEqual(decryptedMobile.name, original.name)
        XCTAssertEqual(decryptedMobile.`private`, original.`private`)
        XCTAssertEqual(decryptedMobile.email, original.email)
        XCTAssertEqual(decryptedMobile.system_metadata, "") // Mobile should NOT have access to system_metadata
        logger.info("Mobile keystore access control verified - can decrypt user fields, cannot decrypt system_only")
        
        // Test decryption with node (should have access to system fields but not user fields)
        logger.trace("Testing decryption with node keystore")
        let decryptedNode = try await encrypted.decryptWithKeystore(nodeKs)
        logger.debug("Node decryption successful - verifying access control")
        XCTAssertEqual(decryptedNode.id, original.id)
        XCTAssertEqual(decryptedNode.name, original.name)
        XCTAssertEqual(decryptedNode.`private`, "") // Should be empty for node
        XCTAssertEqual(decryptedNode.email, original.email)
        XCTAssertEqual(decryptedNode.system_metadata, original.system_metadata) // Node should have access to system_metadata
        logger.info("Node keystore access control verified - can decrypt system fields, cannot decrypt user fields")
    }
    
    func testEncryptionInAnyValue() async throws {
        logger.info("Starting testEncryptionInAnyValue - exactly matching Rust test_encryption_in_arcvalue")
        let (mobileKs, nodeKs, resolver, _, profilePk) = try await buildTestContext()
        
        logger.trace("Creating test profile for AnyValue test")
        let profile = TestProfile(
            id: "789",
            name: "ArcValue Test",
            private: "arc_secret",
            email: "arc@example.com",
            system_metadata: "arc_system_data"
        )
        logger.debug("AnyValue test profile created: id=\(profile.id), name=\(profile.name)")
        
        // Ensure TestProfile is registered before creating AnyValue
        logger.trace("Ensuring TestProfile is registered")
        TestProfile._ensureRegistered()
        logger.info("TestProfile registration complete")
        
        // Create AnyValue with struct
        logger.trace("Creating AnyValue from test profile")
        let val = AnyValue.struct(profile)
        XCTAssertEqual(val.category, .struct)
        logger.debug("AnyValue created with category: \(val.category)")
        
        // Create serialization context - resolve network_public_key from resolver
        logger.trace("Creating serialization context")
        let systemInfo = try resolver.resolveLabelInfo("system")
        let context = SerializationContext(
            keystore: mobileKs,
            resolver: resolver,
            networkId: "test_network",
            profilePublicKey: profilePk
        )
        logger.debug("Serialization context created with networkId: test_network")
        
        // Serialize with encryption
        logger.trace("Serializing AnyValue with encryption context")
        let ser = try await val.serialize(context: context)
        logger.info("AnyValue serialization successful: \(ser.count) bytes")
        
        // Deserialize with node (limited access)
        logger.trace("Deserializing with node keystore (limited access)")
        let deNode = try AnyValue.deserialize(ser, keystore: nodeKs)
        let nodeProfile: TestProfile = try await deNode.asType()
        logger.debug("Node deserialization successful - verifying access control")
        XCTAssertEqual(nodeProfile.id, profile.id)
        XCTAssertEqual(nodeProfile.name, profile.name)
        XCTAssertEqual(nodeProfile.`private`, "")
        XCTAssertEqual(nodeProfile.email, profile.email)
        XCTAssertEqual(nodeProfile.system_metadata, profile.system_metadata) // Node should have access to system_metadata
        logger.info("Node keystore access control verified - can decrypt system fields, cannot decrypt user fields")
        
        // Deserialize with mobile (access to user fields but not system_only)
        logger.trace("Deserializing with mobile keystore (user access)")
        let deMobile = try AnyValue.deserialize(ser, keystore: mobileKs)
        let mobileProfile: TestProfile = try await deMobile.asType()
        logger.debug("Mobile deserialization successful - verifying access control")
        XCTAssertEqual(mobileProfile.id, profile.id)
        XCTAssertEqual(mobileProfile.name, profile.name)
        XCTAssertEqual(mobileProfile.`private`, profile.`private`)
        XCTAssertEqual(mobileProfile.email, profile.email)
        XCTAssertEqual(mobileProfile.system_metadata, "") // Mobile should NOT have access to system_metadata
        logger.info("Mobile keystore access control verified - can decrypt user fields, cannot decrypt system_only")
        
        // Test getting encrypted type directly from AnyValue (matching Rust pattern)
        logger.trace("Testing encrypted type access from AnyValue")
        let nodeProfileEncrypted: TestProfile.EncryptedTestProfile = try await deNode.asType()
        logger.debug("Encrypted type access successful - verifying encrypted fields")
        XCTAssertEqual(nodeProfileEncrypted.id, profile.id)
        XCTAssertNotNil(nodeProfileEncrypted.search_encrypted)
        XCTAssertNotNil(nodeProfileEncrypted.system_encrypted)
        XCTAssertNotNil(nodeProfileEncrypted.user_encrypted)
        XCTAssertNotNil(nodeProfileEncrypted.system_only_encrypted)
        logger.info("Encrypted type access verified - all encrypted field groups present")
        
        // Test decryption of encrypted type with node keystore
        logger.trace("Testing decryption of encrypted type with node keystore")
        let nodeProfileFromEncrypted = try await nodeProfileEncrypted.decryptWithKeystore(nodeKs)
        logger.debug("Node decryption from encrypted type successful - verifying access control")
        XCTAssertEqual(nodeProfileFromEncrypted.id, profile.id)
        XCTAssertEqual(nodeProfileFromEncrypted.name, profile.name)
        XCTAssertEqual(nodeProfileFromEncrypted.`private`, "") // Node should NOT have access to user fields
        XCTAssertEqual(nodeProfileFromEncrypted.email, profile.email)
        XCTAssertEqual(nodeProfileFromEncrypted.system_metadata, profile.system_metadata) // Node should have access to system_metadata
        logger.info("Node keystore access control from encrypted type verified - can decrypt system fields, cannot decrypt user fields")
    }
}
