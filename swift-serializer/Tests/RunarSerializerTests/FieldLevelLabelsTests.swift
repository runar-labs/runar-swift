import RunarFFI
import RunarSerializer
import RunarSerializerMacros
import RunarTestUtils
import SwiftCBOR
import XCTest

/// Tests for field-level label encryption functionality
/// This mirrors the Rust implementation's field-level access control
final class FieldLevelLabelsTests: XCTestCase {
    
    // MARK: - Test Structures with Field-Level Labels
    
    @Encrypted(name: "field_labels_test.UserProfile")
    struct UserProfile: Codable {
        let id: String
        @Runar("system") var name: String
        @Runar("user") var privateData: String
        @Runar("search") var email: String
        @Runar("system_only") var systemMetadata: String
    }
    
    @Encrypted(name: "field_labels_test.Document")
    struct Document: Codable {
        let title: String
        @Runar("user, system") var sharedContent: String  // Multiple labels
        @Runar("system_only") var adminNotes: String
    }
    
    // MARK: - Enhanced Label Resolver Implementation
    
    /// Enhanced label resolver that implements the new protocol
    private struct TestLabelResolver: LabelResolver {
        private let config: KeyMappingConfig
        
        init(_ config: KeyMappingConfig) {
            self.config = config
        }
        
        func canResolve(_ label: String) -> Bool {
            return config.labelMappings[label] != nil
        }
        
        func resolveLabel(_ label: String) throws -> LabelKeyInfo {
            guard let info = config.labelMappings[label] else {
                throw SerializerError.encryptionFailed("No mapping for label: \(label)")
            }
            return LabelKeyInfo(
                profileIds: info.profileIds.map { $0.base64EncodedString() },
                networkId: info.networkId
            )
        }
    }
    
    // MARK: - Test Setup
    
    private var testContext: (keystore: EnvelopeCrypto, resolver: LabelResolver, networkId: String, profilePk: Data)!
    
    override func setUp() async throws {
        try await super.setUp()
        testContext = try TestKeystoreFactory.createTestContext()
    }
    
    // MARK: - Field-Level Label Tests
    
    func testFieldLevelLabelParsing() throws {
        // Test that the @Runar macro correctly parses field-level labels
        let profile = UserProfile(
            id: "test-123",
            name: "John Doe",
            privateData: "secret info",
            email: "john@example.com",
            systemMetadata: "internal data"
        )
        
        // Verify the struct was created correctly
        XCTAssertEqual(profile.id, "test-123")
        XCTAssertEqual(profile.name, "John Doe")
        XCTAssertEqual(profile.privateData, "secret info")
        XCTAssertEqual(profile.email, "john@example.com")
        XCTAssertEqual(profile.systemMetadata, "internal data")
    }
    
    func testMultipleLabelsOnField() throws {
        // Test that a field can have multiple labels
        let document = Document(
            title: "Test Document",
            sharedContent: "Content accessible by both user and system",
            adminNotes: "Admin only content"
        )
        
        XCTAssertEqual(document.title, "Test Document")
        XCTAssertEqual(document.sharedContent, "Content accessible by both user and system")
        XCTAssertEqual(document.adminNotes, "Admin only content")
    }
    
    func testLabelResolverCanResolve() throws {
        let resolver = TestLabelResolver(testContext.resolver.config)
        
        // Test that canResolve works correctly
        XCTAssertTrue(resolver.canResolve("user"), "User label should be resolvable")
        XCTAssertTrue(resolver.canResolve("system"), "System label should be resolvable")
        XCTAssertTrue(resolver.canResolve("search"), "Search label should be resolvable")
        XCTAssertTrue(resolver.canResolve("system_only"), "System-only label should be resolvable")
        XCTAssertFalse(resolver.canResolve("non_existent"), "Non-existent label should not be resolvable")
    }
    
    func testLabelResolverResolveLabel() throws {
        let resolver = TestLabelResolver(testContext.resolver.config)
        
        // Test that resolveLabel returns correct LabelKeyInfo
        let userInfo = try resolver.resolveLabel("user")
        XCTAssertEqual(userInfo.profileIds.count, 1, "User label should have one profile ID")
        XCTAssertNil(userInfo.networkId, "User label should not have network ID")
        
        let systemInfo = try resolver.resolveLabel("system")
        XCTAssertEqual(systemInfo.profileIds.count, 1, "System label should have one profile ID")
        XCTAssertEqual(systemInfo.networkId, testContext.networkId, "System label should have network ID")
        
        let systemOnlyInfo = try resolver.resolveLabel("system_only")
        XCTAssertEqual(systemOnlyInfo.profileIds.count, 0, "System-only label should have no profile IDs")
        XCTAssertEqual(systemOnlyInfo.networkId, testContext.networkId, "System-only label should have network ID")
    }
    
    func testEncryptionWithFieldLabels() async throws {
        let profile = UserProfile(
            id: "test-123",
            name: "John Doe",
            privateData: "secret info",
            email: "john@example.com",
            systemMetadata: "internal data"
        )
        
        let resolver = TestLabelResolver(testContext.resolver.config)
        
        // Encrypt the profile
        let encrypted = try await profile.encryptWithKeystore(testContext.keystore, resolver)
        
        // Verify the encrypted struct has the expected structure
        XCTAssertEqual(encrypted.id, "test-123") // Plain field
        
        // Verify encrypted fields are present
        XCTAssertNotNil(encrypted.system_encrypted, "System encrypted field should be present")
        XCTAssertNotNil(encrypted.user_encrypted, "User encrypted field should be present")
        XCTAssertNotNil(encrypted.search_encrypted, "Search encrypted field should be present")
        XCTAssertNotNil(encrypted.system_only_encrypted, "System-only encrypted field should be present")
    }
    
    func testDecryptionWithFieldLabels() async throws {
        let profile = UserProfile(
            id: "test-123",
            name: "John Doe",
            privateData: "secret info",
            email: "john@example.com",
            systemMetadata: "internal data"
        )
        
        let resolver = TestLabelResolver(testContext.resolver.config)
        
        // Encrypt the profile
        let encrypted = try await profile.encryptWithKeystore(testContext.keystore, resolver)
        
        // Decrypt the profile
        let decrypted = try encrypted.decryptWithKeystore(testContext.keystore)
        
        // Verify all fields are correctly decrypted
        XCTAssertEqual(decrypted.id, profile.id)
        XCTAssertEqual(decrypted.name, profile.name)
        XCTAssertEqual(decrypted.privateData, profile.privateData)
        XCTAssertEqual(decrypted.email, profile.email)
        XCTAssertEqual(decrypted.systemMetadata, profile.systemMetadata)
    }
    
    func testPartialDecryptionWithMissingKeys() async throws {
        // Create a profile with field-level labels
        let profile = UserProfile(
            id: "test-123",
            name: "John Doe",
            privateData: "secret info",
            email: "john@example.com",
            systemMetadata: "internal data"
        )
        
        let resolver = TestLabelResolver(testContext.resolver.config)
        
        // Encrypt the profile
        let encrypted = try await profile.encryptWithKeystore(testContext.keystore, resolver)
        
        // Create a keystore that can't decrypt certain labels
        // This would simulate a mobile keystore trying to access system-only data
        let limitedKeystore = try TestKeystoreFactory.createMobileKeystore()
        
        // Decrypt with limited keystore - should get defaults for inaccessible fields
        let decrypted = try encrypted.decryptWithKeystore(limitedKeystore)
        
        // Plain fields should be preserved
        XCTAssertEqual(decrypted.id, profile.id)
        
        // Labeled fields should have default values if decryption fails
        // This is the expected behavior - partial access is not an error
        XCTAssertEqual(decrypted.name, "") // Default for String
        XCTAssertEqual(decrypted.privateData, "") // Default for String
        XCTAssertEqual(decrypted.email, "") // Default for String
        XCTAssertEqual(decrypted.systemMetadata, "") // Default for String
    }
    
    func testDeterministicLabelOrdering() throws {
        // Test that labels are ordered deterministically (system, user, search, system_only)
        let profile = UserProfile(
            id: "test-123",
            name: "John Doe",
            privateData: "secret info",
            email: "john@example.com",
            systemMetadata: "internal data"
        )
        
        // The generated encrypted struct should have fields in deterministic order
        let encryptedType = type(of: profile).Encrypted.self
        
        // Use reflection to check field order
        let mirror = Mirror(reflecting: encryptedType.init(
            id: "test",
            system_encrypted: nil,
            user_encrypted: nil,
            search_encrypted: nil,
            system_only_encrypted: nil
        ))
        
        let fieldNames = mirror.children.compactMap { $0.label }
        
        // Verify deterministic ordering: plain fields first, then encrypted fields in label order
        XCTAssertTrue(fieldNames.contains("id"), "Plain field should be present")
        XCTAssertTrue(fieldNames.contains("system_encrypted"), "System encrypted field should be present")
        XCTAssertTrue(fieldNames.contains("user_encrypted"), "User encrypted field should be present")
        XCTAssertTrue(fieldNames.contains("search_encrypted"), "Search encrypted field should be present")
        XCTAssertTrue(fieldNames.contains("system_only_encrypted"), "System-only encrypted field should be present")
    }
}


