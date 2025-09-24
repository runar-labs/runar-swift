import RunarSerializer
import SwiftCBOR
import SwiftFFI
import XCTest

/// Tests for Label Group Encryption functionality
final class LabelGroupEncryptionTests: XCTestCase {
    // MARK: - Test Data

    private let testNetworkKey = Data(Array(0 ..< 32)) // Exactly 32 bytes
    private let testProfileKey1 = Data(Array(10 ..< 42)) // Exactly 32 bytes
    private let testProfileKey2 = Data(Array(20 ..< 52)) // Exactly 32 bytes

    private var keystore: TestKeyManagerAdapter!
    private var resolver: LabelResolver!

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
    }

    // MARK: - Test Structures

    struct TestFields: Codable, RunarDefault {
        let id: String
        let value: Int
        let flag: Bool

        static var runarDefaultValue: TestFields {
            TestFields(id: "", value: 0, flag: false)
        }
    }

    // MARK: - Encryption Tests

    func testEncryptLabelGroupSuccess() async throws {
        let testFields = TestFields(id: "test123", value: 42, flag: true)

        let result = try await encryptLabelGroup(
            label: "system",
            fieldsStruct: testFields,
            keystore: keystore,
            resolver: resolver
        )

        XCTAssertEqual(result.label, "system")
        XCTAssertNotNil(result.envelope)
    }

    func testEncryptLabelGroupUnresolvableLabel() async throws {
        let testFields = TestFields(id: "test123", value: 42, flag: true)

        let result = try await encryptLabelGroup(
            label: "nonexistent",
            fieldsStruct: testFields,
            keystore: keystore,
            resolver: resolver
        )

        XCTAssertEqual(result.label, "nonexistent")
        XCTAssertNil(result.envelope)
    }

    func testEncryptLabelGroupUserOnly() async throws {
        let testFields = TestFields(id: "user_data", value: 100, flag: false)

        let result = try await encryptLabelGroup(
            label: "user",
            fieldsStruct: testFields,
            keystore: keystore,
            resolver: resolver
        )

        XCTAssertEqual(result.label, "user")
        XCTAssertNotNil(result.envelope)
    }

    func testEncryptLabelGroupNetworkOnly() async throws {
        let testFields = TestFields(id: "search_data", value: 200, flag: true)

        let result = try await encryptLabelGroup(
            label: "search",
            fieldsStruct: testFields,
            keystore: keystore,
            resolver: resolver
        )

        XCTAssertEqual(result.label, "search")
        XCTAssertNotNil(result.envelope)
    }

    // MARK: - Decryption Tests

    func testDecryptLabelGroupSuccess() async throws {
        let originalFields = TestFields(id: "test123", value: 42, flag: true)

        // Encrypt first
        let encryptedGroup = try await encryptLabelGroup(
            label: "system",
            fieldsStruct: originalFields,
            keystore: keystore,
            resolver: resolver
        )

        // Decrypt
        let decryptedFields: TestFields = try await decryptLabelGroup(
            encryptedGroup: encryptedGroup,
            keystore: keystore
        )

        XCTAssertEqual(decryptedFields.id, originalFields.id)
        XCTAssertEqual(decryptedFields.value, originalFields.value)
        XCTAssertEqual(decryptedFields.flag, originalFields.flag)
    }

    func testDecryptLabelGroupWithNilEnvelope() async throws {
        let encryptedGroup = EncryptedLabelGroup(label: "nonexistent", envelope: nil)

        let decryptedFields: TestFields = try await decryptLabelGroup(
            encryptedGroup: encryptedGroup,
            keystore: keystore
        )

        // Should return default value when envelope is nil
        XCTAssertEqual(decryptedFields.id, "")
        XCTAssertEqual(decryptedFields.value, 0)
        XCTAssertEqual(decryptedFields.flag, false)
    }

    func testDecryptLabelGroupWithInvalidEnvelope() async throws {
        // Create an encrypted group with invalid envelope data
        let invalidEnvelope = Data("invalid envelope data".utf8)
        let encryptedGroup = EncryptedLabelGroup(label: "system", envelope: invalidEnvelope)

        // Should return default value when decryption fails
        let decryptedFields: TestFields = try await decryptLabelGroup(
            encryptedGroup: encryptedGroup,
            keystore: keystore
        )

        XCTAssertEqual(decryptedFields.id, "")
        XCTAssertEqual(decryptedFields.value, 0)
        XCTAssertEqual(decryptedFields.flag, false)
    }

    // MARK: - Round Trip Tests

    func testEncryptDecryptRoundTrip() async throws {
        let originalFields = TestFields(id: "roundtrip_test", value: 999, flag: true)

        // Test system label
        let systemEncrypted = try await encryptLabelGroup(
            label: "system",
            fieldsStruct: originalFields,
            keystore: keystore,
            resolver: resolver
        )

        let systemDecrypted: TestFields = try await decryptLabelGroup(
            encryptedGroup: systemEncrypted,
            keystore: keystore
        )

        XCTAssertEqual(systemDecrypted.id, originalFields.id)
        XCTAssertEqual(systemDecrypted.value, originalFields.value)
        XCTAssertEqual(systemDecrypted.flag, originalFields.flag)

        // Test user label
        let userEncrypted = try await encryptLabelGroup(
            label: "user",
            fieldsStruct: originalFields,
            keystore: keystore,
            resolver: resolver
        )

        let userDecrypted: TestFields = try await decryptLabelGroup(
            encryptedGroup: userEncrypted,
            keystore: keystore
        )

        XCTAssertEqual(userDecrypted.id, originalFields.id)
        XCTAssertEqual(userDecrypted.value, originalFields.value)
        XCTAssertEqual(userDecrypted.flag, originalFields.flag)
    }

    // MARK: - Label Resolver Integration Tests

    func testLabelResolverIntegration() async throws {
        // Test that resolver correctly identifies available labels
        XCTAssertTrue(resolver.canResolve("system"))
        XCTAssertTrue(resolver.canResolve("user"))
        XCTAssertTrue(resolver.canResolve("search"))
        XCTAssertFalse(resolver.canResolve("nonexistent"))

        // Test label info resolution
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

    func testAvailableLabels() async throws {
        let availableLabels = resolver.availableLabels()
        XCTAssertEqual(availableLabels.count, 3)
        XCTAssertTrue(availableLabels.contains("system"))
        XCTAssertTrue(availableLabels.contains("user"))
        XCTAssertTrue(availableLabels.contains("search"))
    }
}
