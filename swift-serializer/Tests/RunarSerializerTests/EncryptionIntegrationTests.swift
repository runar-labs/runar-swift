import RunarFFI
import RunarSerializer
import RunarSerializerMacros
import RunarTestUtils
import SwiftCBOR
import XCTest

/// Swift equivalent of Rust's encryption_test.rs
/// Tests comprehensive encryption functionality with real keystores
final class EncryptionIntegrationTests: XCTestCase {
    
    // MARK: - Test Structures (Mirroring Rust exactly)
    
    @Encrypted(name: "encryption_test.TestProfile")
    struct TestProfile: Codable {
        let id: String
        @Runar("system") var name: String
        @Runar("user") var privateData: String
        @Runar("search") var email: String
        @Runar("system_only") var systemMetadata: String
    }
    
    // Simple test structure for basic encryption
    @Encrypted(name: "encryption_test.SimpleData")
    struct SimpleData: Codable {
        let id: Int
        @Runar("user") var secret: String
        @Runar("system") var shared: String
    }
    
    // MARK: - Label Resolver Adapter
    
    /// Adapter to convert TestLabelResolver to LabelResolver
    private struct LabelResolverAdapter: RunarSerializer.LabelResolver {
        private let testResolver: RunarTestUtils.TestLabelResolver
        
        init(_ testResolver: RunarTestUtils.TestLabelResolver) {
            self.testResolver = testResolver
        }
        
        func resolveLabel(_ label: String) -> RunarSerializer.LabelKeyInfo? {
            guard let testInfo = testResolver.resolveLabel(label) else { return nil }
            return RunarSerializer.LabelKeyInfo(
                profileIds: testInfo.profileIds.map { $0.base64EncodedString() },
                networkId: testInfo.networkId
            )
        }
    }
    
    // MARK: - Debug Test
    
    func testMacroRegistrationDebug() async throws {
        // Debug test to see what's happening with macro registration
        
        // 1. Check what's in the registry before we start
        let registry = SerializationRegistry.shared
        print("🔍 Registry state before macro usage:")
        print("   - Wire names: \(await registry.wireNames)")
        print("   - Decoders: \(await registry.decoders.keys)")
        print("   - Encryptors: \(await registry.encryptors.keys)")
        
        // 2. Create a test profile to trigger macro registration
        let profile = TestProfile(
            id: "debug_123",
            name: "Debug User",
            privateData: "Debug data",
            email: "debug@example.com",
            systemMetadata: "Debug metadata"
        )
        
        // 3. Call toAnyValue to trigger registration
        print("🔍 Calling toAnyValue() to trigger registration...")
        let anyValue = profile.toAnyValue()
        print("🔍 toAnyValue() completed, anyValue type: \(type(of: anyValue))")
        
        // 4. Wait a bit for registration to complete
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // 5. Check registry state after registration
        print("🔍 Registry state after macro usage:")
        print("   - Wire names: \(await registry.wireNames)")
        print("   - Decoders: \(await registry.decoders.keys)")
        print("   - Encryptors: \(await registry.encryptors.keys)")
        
        // 6. Check if our wire name is registered
        let testProfileWireName = "TestProfile"
        let isRegistered = await registry.wireNames.contains(testProfileWireName)
        print("🔍 Is '\(testProfileWireName)' registered? \(isRegistered)")
        
        // 7. Try to get the decoder
        let decoder = await registry.decoder(for: testProfileWireName)
        print("🔍 Decoder for '\(testProfileWireName)': \(decoder != nil ? "Found" : "Not found")")
        
        // For now, just assert that we can create the anyValue
        XCTAssertNotNil(anyValue, "AnyValue should be created successfully")
    }
    
    // MARK: - Test Setup
    
    func testBasicEncryptionFlow() async throws {
        // 1. Setup real keystores (simulating node setup)
        let (userMobileKs, _, resolver, networkId, profilePk) = try TestKeystoreFactory.createTestContext()
        
        // 2. Create test data with @Encrypted macro
        let profile = TestProfile(
            id: "test_123",
            name: "Test User",
            privateData: "This is private information",
            email: "test@example.com",
            systemMetadata: "System-level metadata"
        )
        
        // 3. Ensure macro registration is complete before testing
        // The macro generates async registration, so we need to trigger it first
        _ = profile.toAnyValue() // This triggers the registration task
        try await Task.sleep(nanoseconds: 200_000_000) // Wait 0.2 seconds for registration to complete
        
        // 4. Test encryption via serializer
        let context = SerializationContext(
            keystore: FFIKeyStore(keys: userMobileKs),
            resolver: LabelResolverAdapter(resolver),
            networkId: networkId,
            profilePublicKey: profilePk
        )
        
        let anyValue = profile.toAnyValue()
        let encryptedData = try await anyValue.serialize(context: context)
        
        // 5. Verify encryption produced data
        XCTAssertFalse(encryptedData.isEmpty, "Encryption should produce non-empty data")
        XCTAssertNotEqual(encryptedData, try JSONEncoder().encode(profile), "Encrypted data should not equal plain JSON")
        
        // 6. Test deserialization
        let deserializedAnyValue = try AnyValue.deserialize(encryptedData, keystore: FFIKeyStore(keys: userMobileKs))
        let deserializedProfile: TestProfile = try await deserializedAnyValue.asType()
        
        // 7. Verify all fields are preserved
        XCTAssertEqual(deserializedProfile.id, profile.id)
        XCTAssertEqual(deserializedProfile.name, profile.name)
        XCTAssertEqual(deserializedProfile.privateData, profile.privateData)
        XCTAssertEqual(deserializedProfile.email, profile.email)
        XCTAssertEqual(deserializedProfile.systemMetadata, profile.systemMetadata)
    }
    
    func testSimpleDataEncryption() async throws {
        // 1. Setup real keystores
        let (userMobileKs, _, resolver, networkId, profilePk) = try TestKeystoreFactory.createTestContext()
        
        // 2. Create simple test data
        let simpleData = SimpleData(
            id: 42,
            secret: "Super secret information",
            shared: "Information shared with system"
        )
        
        // 3. Ensure macro registration is complete before testing
        // The macro generates async registration, so we need to trigger it first
        _ = simpleData.toAnyValue() // This triggers the registration task
        try await Task.sleep(nanoseconds: 200_000_000) // Wait 0.2 seconds for registration to complete
        
        // 4. Test encryption
        let context = SerializationContext(
            keystore: FFIKeyStore(keys: userMobileKs),
            resolver: LabelResolverAdapter(resolver),
            networkId: networkId,
            profilePublicKey: profilePk
        )
        
        let anyValue = simpleData.toAnyValue()
        let encryptedData = try await anyValue.serialize(context: context)
        
        // 5. Verify encryption
        XCTAssertFalse(encryptedData.isEmpty, "Encryption should produce data")
        
        // 6. Test decryption
        let deserializedAnyValue = try AnyValue.deserialize(encryptedData, keystore: FFIKeyStore(keys: userMobileKs))
        let deserializedData: SimpleData = try await deserializedAnyValue.asType()
        
        // 7. Verify data integrity
        XCTAssertEqual(deserializedData.id, simpleData.id)
        XCTAssertEqual(deserializedData.secret, simpleData.secret)
        XCTAssertEqual(deserializedData.shared, simpleData.shared)
    }
    
    func testKeystoreFactoryCreatesValidKeystores() throws {
        // Test that our keystore factory creates working keystores
        
        // 1. Test mobile keystore creation
        let mobileKs = try TestKeystoreFactory.createMobileKeystore()
        XCTAssertNotNil(mobileKs, "Mobile keystore should be created")
        
        // 2. Test node keystore creation
        let nodeKs = try TestKeystoreFactory.createNodeKeystore()
        XCTAssertNotNil(nodeKs, "Node keystore should be created")
        
        // 3. Test CA and node setup
        let (ca, node, networkId) = try TestKeystoreFactory.createCAAndNode()
        XCTAssertNotNil(ca, "CA keystore should be created")
        XCTAssertNotNil(node, "Node keystore should be created")
        XCTAssertFalse(networkId.isEmpty, "Network ID should be generated")
        
        // 4. Test complete test context
        let (userMobile, nodeKs2, resolver, networkId2, profilePk) = try TestKeystoreFactory.createTestContext()
        XCTAssertNotNil(userMobile, "User mobile keystore should be created")
        XCTAssertNotNil(nodeKs2, "Node keystore should be created")
        XCTAssertNotNil(resolver, "Label resolver should be created")
        XCTAssertFalse(networkId2.isEmpty, "Network ID should be generated")
        XCTAssertFalse(profilePk.isEmpty, "Profile key should be generated")
    }
    
    func testLabelResolverConfiguration() throws {
        // Test that our label resolver is configured correctly
        
        let (_, _, resolver, networkId, profilePk) = try TestKeystoreFactory.createTestContext()
        
        // Test user label (profile only)
        let userInfo = resolver.resolveLabel("user")
        XCTAssertNotNil(userInfo, "User label should be resolvable")
        XCTAssertEqual(userInfo?.profileIds.count, 1, "User label should have one profile ID")
        XCTAssertEqual(userInfo?.profileIds.first, profilePk, "User label should have correct profile ID")
        XCTAssertNil(userInfo?.networkId, "User label should not have network ID")
        
        // Test system label (profile + network)
        let systemInfo = resolver.resolveLabel("system")
        XCTAssertNotNil(systemInfo, "System label should be resolvable")
        XCTAssertEqual(systemInfo?.profileIds.count, 1, "System label should have one profile ID")
        XCTAssertEqual(systemInfo?.profileIds.first, profilePk, "System label should have correct profile ID")
        XCTAssertEqual(systemInfo?.networkId, networkId, "System label should have correct network ID")
        
        // Test system_only label (network only)
        let systemOnlyInfo = resolver.resolveLabel("system_only")
        XCTAssertNotNil(systemOnlyInfo, "System-only label should be resolvable")
        XCTAssertEqual(systemOnlyInfo?.profileIds.count, 0, "System-only label should have no profile IDs")
        XCTAssertEqual(systemOnlyInfo?.networkId, networkId, "System-only label should have correct network ID")
        
        // Test search label (profile + network)
        let searchInfo = resolver.resolveLabel("search")
        XCTAssertNotNil(searchInfo, "Search label should be resolvable")
        XCTAssertEqual(searchInfo?.profileIds.count, 1, "Search label should have one profile ID")
        XCTAssertEqual(searchInfo?.profileIds.first, profilePk, "Search label should have correct profile ID")
        XCTAssertEqual(searchInfo?.networkId, networkId, "Search label should have correct network ID")
        
        // Test non-existent label
        let nonExistentInfo = resolver.resolveLabel("non_existent")
        XCTAssertNil(nonExistentInfo, "Non-existent label should return nil")
    }
}
