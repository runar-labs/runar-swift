import RunarSerializer
import SwiftCBOR
import SwiftFFI
import XCTest

/// Comprehensive integration tests that demonstrate the full functionality
/// of the Swift serializer with label-based encryption
final class ComprehensiveIntegrationTests: XCTestCase {
    // MARK: - Test Data

    private let testNetworkKey = Data(Array(0 ..< 32)) // Exactly 32 bytes
    private let testProfileKey1 = Data(Array(10 ..< 42)) // Exactly 32 bytes
    private let testProfileKey2 = Data(Array(20 ..< 52)) // Exactly 32 bytes

    private var keystore: TestKeyManagerAdapter!
    private var resolver: LabelResolver!
    private var context: SerializationContext!

    override func setUp() async throws {
        try await super.setUp()

        // Create a test keystore adapter
        keystore = TestKeyManagerAdapter()

        let config = LabelResolverConfig(labelMappings: [
            "system": LabelValue(networkPublicKey: testNetworkKey, userKeySpec: .currentUser),
            "user": LabelValue(networkPublicKey: nil, userKeySpec: .currentUser),
            "search": LabelValue(networkPublicKey: testNetworkKey, userKeySpec: nil),
        ])

        resolver = try LabelResolver.createContextResolver(
            systemConfig: config,
            userProfilePublicKeys: [testProfileKey1, testProfileKey2]
        )

        context = SerializationContext(
            keystore: keystore,
            resolver: resolver,
            networkId: "test_network",
            profilePublicKey: testProfileKey1
        )
    }

    // MARK: - Test Structures

    struct TestUserProfile: Codable, RunarDefault {
        let id: String
        let name: String
        let email: String
        let preferences: [String: String]

        static var runarDefaultValue: TestUserProfile {
            TestUserProfile(id: "", name: "", email: "", preferences: [:])
        }
    }

    struct TestSystemConfig: Codable, RunarDefault {
        let version: String
        let features: [String]
        let settings: [String: Bool]

        static var runarDefaultValue: TestSystemConfig {
            TestSystemConfig(version: "", features: [], settings: [:])
        }
    }

    // MARK: - Label Group Encryption Tests

    func testLabelGroupEncryptionRoundTrip() async throws {
        let userProfile = TestUserProfile(
            id: "user123",
            name: "John Doe",
            email: "john@example.com",
            preferences: ["theme": "dark", "notifications": "enabled"]
        )

        let systemConfig = TestSystemConfig(
            version: "1.0.0",
            features: ["encryption", "sync"],
            settings: ["debug": false, "analytics": true]
        )

        // Test user label encryption
        let userEncrypted = try await encryptLabelGroup(
            label: "user",
            fieldsStruct: userProfile,
            keystore: keystore,
            resolver: resolver
        )

        XCTAssertEqual(userEncrypted.label, "user")
        XCTAssertNotNil(userEncrypted.envelope)

        // Test system label encryption
        let systemEncrypted = try await encryptLabelGroup(
            label: "system",
            fieldsStruct: systemConfig,
            keystore: keystore,
            resolver: resolver
        )

        XCTAssertEqual(systemEncrypted.label, "system")
        XCTAssertNotNil(systemEncrypted.envelope)

        // Test decryption
        let decryptedUser: TestUserProfile = try await decryptLabelGroup(
            encryptedGroup: userEncrypted,
            keystore: keystore
        )

        XCTAssertEqual(decryptedUser.id, userProfile.id)
        XCTAssertEqual(decryptedUser.name, userProfile.name)
        XCTAssertEqual(decryptedUser.email, userProfile.email)
        XCTAssertEqual(decryptedUser.preferences, userProfile.preferences)

        let decryptedSystem: TestSystemConfig = try await decryptLabelGroup(
            encryptedGroup: systemEncrypted,
            keystore: keystore
        )

        XCTAssertEqual(decryptedSystem.version, systemConfig.version)
        XCTAssertEqual(decryptedSystem.features, systemConfig.features)
        XCTAssertEqual(decryptedSystem.settings, systemConfig.settings)
    }

    // MARK: - AnyValue Integration Tests

    func testAnyValueSerializationWithContext() async throws {
        let testData = TestUserProfile(
            id: "test_user",
            name: "Test User",
            email: "test@example.com",
            preferences: ["theme": "light"]
        )

        // Create AnyValue from struct
        let anyValue = AnyValue.struct(testData)

        // Test that serialization with context fails for unregistered types (strict design)
        do {
            _ = try await anyValue.serialize(context: context)
            XCTFail("Should have thrown an error for unregistered type")
        } catch let SerializerError.serializationFailed(message) {
            XCTAssertTrue(message.contains("Missing encryptor for TestUserProfile"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testAnyValueSerializationWithoutContext() async throws {
        let testData = TestUserProfile(
            id: "test_user",
            name: "Test User",
            email: "test@example.com",
            preferences: ["theme": "light"]
        )

        // Create AnyValue from struct
        let anyValue = AnyValue.struct(testData)

        // Serialize without context (should use plain serialization)
        let serializedData = try await anyValue.serialize(context: nil)

        XCTAssertFalse(serializedData.isEmpty)

        // Deserialize back
        let deserializedValue = try AnyValue.deserialize(serializedData)
        let deserializedData: TestUserProfile = try await deserializedValue.asType()

        XCTAssertEqual(deserializedData.id, testData.id)
        XCTAssertEqual(deserializedData.name, testData.name)
        XCTAssertEqual(deserializedData.email, testData.email)
        XCTAssertEqual(deserializedData.preferences, testData.preferences)
    }

    // MARK: - Label Resolver Tests

    func testLabelResolverFunctionality() async throws {
        // Test available labels
        let availableLabels = resolver.availableLabels()
        XCTAssertEqual(availableLabels.count, 3)
        XCTAssertTrue(availableLabels.contains("system"))
        XCTAssertTrue(availableLabels.contains("user"))
        XCTAssertTrue(availableLabels.contains("search"))

        // Test canResolve
        XCTAssertTrue(resolver.canResolve("system"))
        XCTAssertTrue(resolver.canResolve("user"))
        XCTAssertTrue(resolver.canResolve("search"))
        XCTAssertFalse(resolver.canResolve("nonexistent"))

        // Test resolveLabelInfo
        let systemInfo = try resolver.resolveLabelInfo("system")
        XCTAssertNotNil(systemInfo.networkPublicKey)
        XCTAssertEqual(systemInfo.profilePublicKeys.count, 2)

        let userInfo = try resolver.resolveLabelInfo("user")
        XCTAssertNil(userInfo.networkPublicKey)
        XCTAssertEqual(userInfo.profilePublicKeys.count, 2)

        let searchInfo = try resolver.resolveLabelInfo("search")
        XCTAssertNotNil(searchInfo.networkPublicKey)
        XCTAssertEqual(searchInfo.profilePublicKeys.count, 0)
    }

    // MARK: - Error Handling Tests

    func testLabelResolverErrorHandling() async throws {
        // Test unresolvable label
        XCTAssertFalse(resolver.canResolve("nonexistent"))

        do {
            _ = try resolver.resolveLabelInfo("nonexistent")
            XCTFail("Should have thrown an error")
        } catch let LabelResolverError.labelUnavailable(label) {
            XCTAssertEqual(label, "nonexistent")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Performance Tests

    func testEncryptionPerformance() async throws {
        let testData = TestUserProfile(
            id: "perf_test",
            name: "Performance Test",
            email: "perf@example.com",
            preferences: ["theme": "dark", "notifications": "enabled", "language": "en"]
        )

        // Simple performance test without measure block to avoid concurrency issues
        let startTime = CFAbsoluteTimeGetCurrent()

        let encrypted = try await encryptLabelGroup(
            label: "system",
            fieldsStruct: testData,
            keystore: keystore,
            resolver: resolver
        )

        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        XCTAssertNotNil(encrypted.envelope)
        XCTAssertLessThan(timeElapsed, 1.0) // Should complete within 1 second
    }
}
