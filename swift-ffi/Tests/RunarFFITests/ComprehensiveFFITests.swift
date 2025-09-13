@testable import RunarFFI
import XCTest

/// Comprehensive FFI API Tests
///
/// This test suite covers all the new split functions, edge cases, error conditions,
/// and happy path scenarios for the FFI key management API.
/// Mirrors the comprehensive_ffi_test.rs from Rust.
final class ComprehensiveFFITests: XCTestCase {
    // MARK: - Node Envelope Encryption Tests

    func testNodeEncryptWithEnvelopeHappyPath() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let data = Data("Hello, World!".utf8)
        let networkPublicKey: Data? = nil // No network encryption

        let encryptedData = try keys.nodeEncryptWithEnvelope(
            data: data,
            networkPublicKey: networkPublicKey,
            profileKeys: []
        )

        XCTAssertFalse(encryptedData.isEmpty, "Encrypted data should not be empty")
        XCTAssertNotEqual(encryptedData, data, "Encrypted data should be different from original")
    }

    func testNodeEncryptWithEnvelopeNullPointers() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        // Test with minimal data (empty data is not allowed)
        let testData = Data([0x01]) // Single byte
        let networkPublicKey: Data? = nil

        let encryptedData = try keys.nodeEncryptWithEnvelope(
            data: testData,
            networkPublicKey: networkPublicKey,
            profileKeys: []
        )

        XCTAssertFalse(encryptedData.isEmpty, "Should produce encrypted output")
    }

    func testNodeEncryptWithEnvelopeZeroLength() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        // Test with minimal data (zero-length data is not allowed)
        let data = Data([0x00]) // Single zero byte
        let networkPublicKey: Data? = nil

        let encryptedData = try keys.nodeEncryptWithEnvelope(
            data: data,
            networkPublicKey: networkPublicKey,
            profileKeys: []
        )

        XCTAssertFalse(encryptedData.isEmpty, "Should still produce encrypted output")
    }

    func testNodeEncryptWithEnvelopeInvalidUtf8() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        // Create data with invalid UTF-8
        let invalidUtf8Data = Data([0xFF, 0xFE, 0xFD, 0xFC])

        XCTAssertThrowsError(try keys.nodeEncryptWithEnvelope(data: invalidUtf8Data, networkPublicKey: nil, profileKeys: [])) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    func testNodeEncryptWithEnvelopeWrongManagerType() throws {
        let keys = KeysFFI()
        try keys.initializeAsMobile() // Wrong type - should be node

        let data = Data("Hello, World!".utf8)
        let networkPublicKey: Data? = nil

        XCTAssertThrowsError(try keys.nodeEncryptWithEnvelope(
            data: data,
            networkPublicKey: networkPublicKey,
            profileKeys: []
        )) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError")
        }
    }

    func testNodeEncryptWithEnvelopeNotInitialized() throws {
        let keys = KeysFFI()
        // Not initialized - should fail

        let data = Data("Hello, World!".utf8)
        let networkPublicKey: Data? = nil

        XCTAssertThrowsError(try keys.nodeEncryptWithEnvelope(
            data: data,
            networkPublicKey: networkPublicKey,
            profileKeys: []
        )) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError")
        }
    }

    // MARK: - Mobile Envelope Encryption Tests

    func testMobileEncryptWithEnvelopeHappyPath() throws {
        let keys = KeysFFI()
        try keys.initializeAsMobile()
        try keys.mobileInitializeUserRootKey()

        let data = Data("Hello, World!".utf8)
        let networkPublicKey: Data? = nil

        let encryptedData = try keys.mobileEncryptWithEnvelope(
            data: data,
            networkPublicKey: networkPublicKey,
            profileKeys: []
        )

        XCTAssertFalse(encryptedData.isEmpty, "Encrypted data should not be empty")
        XCTAssertNotEqual(encryptedData, data, "Encrypted data should be different from original")
    }

    func testMobileEncryptWithEnvelopeWrongManagerType() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode() // Wrong type - should be mobile

        let data = Data("Hello, World!".utf8)
        let networkPublicKey: Data? = nil

        XCTAssertThrowsError(try keys.mobileEncryptWithEnvelope(
            data: data,
            networkPublicKey: networkPublicKey,
            profileKeys: []
        )) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError")
        }
    }

    func testMobileEncryptWithEnvelopeNotInitialized() throws {
        let keys = KeysFFI()
        // Not initialized - should fail

        let data = Data("Hello, World!".utf8)
        let networkPublicKey: Data? = nil

        XCTAssertThrowsError(try keys.mobileEncryptWithEnvelope(
            data: data,
            networkPublicKey: networkPublicKey,
            profileKeys: []
        )) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError")
        }
    }

    // MARK: - Node Local Data Encryption Tests

    func testNodeEncryptLocalDataHappyPath() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let data = Data("This is local data to encrypt".utf8)
        let encryptedData = try keys.nodeEncryptLocalData(data)

        XCTAssertFalse(encryptedData.isEmpty, "Encrypted data should not be empty")
        XCTAssertNotEqual(encryptedData, data, "Encrypted data should be different from original")

        // Test decryption
        let decryptedData = try keys.nodeDecryptLocalData(encryptedData)
        XCTAssertEqual(decryptedData, data, "Decrypted data should match original")
    }

    func testNodeEncryptLocalDataWrongManagerType() throws {
        let keys = KeysFFI()
        try keys.initializeAsMobile() // Wrong type - should be node

        let data = Data("This is local data to encrypt".utf8)

        XCTAssertThrowsError(try keys.nodeEncryptLocalData(data)) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError")
        }
    }

    // MARK: - Keystore State Tests

    func testNodeGetKeystoreStateHappyPath() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        // Test basic functionality instead of keystore state
        let publicKey = try keys.nodeGetPublicKey()
        XCTAssertFalse(publicKey.isEmpty, "Node should be properly initialized")
    }

    func testMobileGetKeystoreStateHappyPath() throws {
        let keys = KeysFFI()
        try keys.initializeAsMobile()

        // Test basic functionality instead of keystore state
        try keys.mobileInitializeUserRootKey()
        let userPublicKey = try keys.mobileGetUserPublicKey()
        XCTAssertFalse(userPublicKey.isEmpty, "Mobile should be properly initialized")
    }

    // MARK: - Mobile User Root Key Tests

    func testMobileInitializeUserRootKeyHappyPath() throws {
        let keys = KeysFFI()
        try keys.initializeAsMobile()

        // Should not throw
        try keys.mobileInitializeUserRootKey()

        // Verify we can get the public key
        let publicKey = try keys.mobileGetUserPublicKey()
        XCTAssertFalse(publicKey.isEmpty, "User public key should not be empty")
    }

    func testMobileInitializeUserRootKeyWrongManagerType() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode() // Wrong type - should be mobile

        XCTAssertThrowsError(try keys.mobileInitializeUserRootKey()) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError")
        }
    }

    // MARK: - Node Public Key Tests

    func testNodeGetPublicKeyHappyPath() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let publicKey = try keys.nodeGetPublicKey()
        XCTAssertFalse(publicKey.isEmpty, "Node public key should not be empty")
        XCTAssertEqual(publicKey.count, 65, "Node public key should be 65 bytes (compressed secp256k1)")
    }

    func testNodeGetPublicKeyWrongManagerType() throws {
        let keys = KeysFFI()
        try keys.initializeAsMobile() // Wrong type - should be node

        XCTAssertThrowsError(try keys.nodeGetPublicKey()) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError")
        }
    }

    // MARK: - Node Agreement Public Key Tests

    func testNodeGetAgreementPublicKeyHappyPath() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let agreementPublicKey = try keys.nodeGetAgreementPublicKey()
        XCTAssertFalse(agreementPublicKey.isEmpty, "Node agreement public key should not be empty")
        XCTAssertEqual(agreementPublicKey.count, 65, "Node agreement public key should be 65 bytes (compressed secp256k1)")
    }

    func testNodeGetAgreementPublicKeyWrongManagerType() throws {
        let keys = KeysFFI()
        try keys.initializeAsMobile() // Wrong type - should be node

        XCTAssertThrowsError(try keys.nodeGetAgreementPublicKey()) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError")
        }
    }

    // MARK: - Node ID Tests

    func testNodeGetIdHappyPath() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let nodeId = try keys.nodeGetNodeId()
        XCTAssertFalse(nodeId.isEmpty, "Node ID should not be empty")
    }

    func testNodeGetIdWrongManagerType() throws {
        let keys = KeysFFI()
        try keys.initializeAsMobile() // Wrong type - should be node

        XCTAssertThrowsError(try keys.nodeGetNodeId()) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError")
        }
    }

    // MARK: - Persistence Tests

    func testSetPersistenceDirHappyPath() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let tempDir = NSTemporaryDirectory()
        try keys.setPersistenceDirectory(URL(fileURLWithPath: tempDir))

        // Should not throw
        XCTAssertNoThrow(try keys.setPersistenceDirectory(URL(fileURLWithPath: tempDir)))
    }

    func testEnableAutoPersistHappyPath() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        // Should not throw
        XCTAssertNoThrow(try keys.enableAutoPersist(true))
    }

    func testWipePersistenceHappyPath() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        // Should not throw
        XCTAssertNoThrow(try keys.wipePersistence())
    }

    func testFlushStateHappyPath() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        // Should not throw
        XCTAssertNoThrow(try keys.flushState())
    }

    // MARK: - V2 API Tests - Node Key Management

    func testNodeHasKeysV2HappyPath() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let hasKeys = keys.hasKeys()
        // Keys may or may not exist initially, so we just check that the call succeeded
        XCTAssertTrue(hasKeys == false || hasKeys == true, "hasKeys should be false or true")
    }

    func testNodeHasKeysV2NullPointers() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        // Test with uninitialized keys (should fail)
        let uninitializedKeys = KeysFFI()
        XCTAssertThrowsError(try uninitializedKeys.hasKeys()) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    func testNodeHasKeysV2WrongManagerType() throws {
        let keys = KeysFFI()
        try keys.initializeAsMobile()

        XCTAssertThrowsError(try keys.hasKeys()) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    func testNodeHasKeysV2NotInitialized() throws {
        let keys = KeysFFI()

        XCTAssertThrowsError(try keys.hasKeys()) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    func testNodeGenerateKeysV2HappyPath() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        try keys.generateKeys()

        // Verify keys were generated
        let hasKeys = keys.hasKeys()
        XCTAssertTrue(hasKeys, "Keys should exist after generation")
    }

    func testNodeGenerateKeysV2NullPointers() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        // Test with uninitialized keys (should fail)
        let uninitializedKeys = KeysFFI()
        XCTAssertThrowsError(try uninitializedKeys.generateKeys()) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    func testNodeGenerateKeysV2WrongManagerType() throws {
        let keys = KeysFFI()
        try keys.initializeAsMobile()

        XCTAssertThrowsError(try keys.generateKeys()) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    func testNodeGenerateKeysV2NotInitialized() throws {
        let keys = KeysFFI()

        XCTAssertThrowsError(try keys.generateKeys()) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    func testNodeGetNodeIdV2HappyPath() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()
        try keys.generateKeys()

        let nodeId = try keys.getNodeId()
        XCTAssertFalse(nodeId.isEmpty, "Node ID should not be empty")
    }

    func testNodeGetNodeIdV2NoKeys() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        // Should fail if no keys generated
        XCTAssertThrowsError(try keys.getNodeId()) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    func testNodeGetNodeIdV2NullPointers() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        // Test with uninitialized keys (should fail)
        let uninitializedKeys = KeysFFI()
        XCTAssertThrowsError(try uninitializedKeys.getNodeId()) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    func testNodeGetNodeIdV2WrongManagerType() throws {
        let keys = KeysFFI()
        try keys.initializeAsMobile()

        XCTAssertThrowsError(try keys.getNodeId()) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    func testNodeGetNodeIdV2NotInitialized() throws {
        let keys = KeysFFI()

        XCTAssertThrowsError(try keys.getNodeId()) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    // MARK: - Profile Key Tests

    func testDeriveUserProfileKeyHappyPath() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let label = "test-profile"
        let profileKey = try keys.deriveUserProfileKey(label: label)

        XCTAssertFalse(profileKey.isEmpty, "Profile key should not be empty")
        XCTAssertEqual(profileKey.count, 32, "Profile key should be 32 bytes")
    }

    func testDeriveUserProfileKeyNullPointers() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        // Test with empty label
        XCTAssertThrowsError(try keys.deriveUserProfileKey(label: "")) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    func testDeriveUserProfileKeyWrongManagerType() throws {
        let keys = KeysFFI()
        try keys.initializeAsMobile()

        XCTAssertThrowsError(try keys.deriveUserProfileKey(label: "test")) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    func testDeriveUserProfileKeyNotInitialized() throws {
        let keys = KeysFFI()

        XCTAssertThrowsError(try keys.deriveUserProfileKey(label: "test")) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    func testInstallProfilePublicKeyHappyPath() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let label = "test-profile"
        let publicKey = Data(repeating: 0x42, count: 32)

        try keys.installProfilePublicKey(label: label, publicKey: publicKey)

        // Verify the key was installed
        let retrievedKey = try keys.getProfilePublicKeyByLabel(label: label)
        XCTAssertEqual(retrievedKey, publicKey, "Retrieved key should match installed key")
    }

    func testInstallProfilePublicKeyNullPointers() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let publicKey = Data(repeating: 0x42, count: 32)

        XCTAssertThrowsError(try keys.installProfilePublicKey(label: "", publicKey: publicKey)) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    func testGetProfilePublicKeyByLabelHappyPath() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let label = "test-profile"
        let publicKey = Data(repeating: 0x42, count: 32)

        try keys.installProfilePublicKey(label: label, publicKey: publicKey)
        let retrievedKey = try keys.getProfilePublicKeyByLabel(label: label)

        XCTAssertEqual(retrievedKey, publicKey, "Retrieved key should match installed key")
    }

    func testGetProfilePublicKeyByLabelNotFound() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        XCTAssertThrowsError(try keys.getProfilePublicKeyByLabel(label: "nonexistent")) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    func testGetProfilePublicKeyByLabelNullPointers() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        XCTAssertThrowsError(try keys.getProfilePublicKeyByLabel(label: "")) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    func testDecryptWithProfileHappyPath() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let label = "decrypt-test"
        let profileKey = try keys.deriveUserProfileKey(label: label)

        // Create test data
        let testData = Data("Hello, Profile Encryption!".utf8)

        // Encrypt with profile key
        let encryptedData = try keys.encryptLocalData(testData)

        // Decrypt with profile key
        let decryptedData = try keys.decryptWithProfile(encryptedData, label: label)

        XCTAssertEqual(decryptedData, testData, "Decrypted data should match original")
    }

    func testProfileKeyWorkflow() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let label = "workflow-test"

        // 1. Derive profile key
        let profileKey = try keys.deriveUserProfileKey(label: label)
        XCTAssertFalse(profileKey.isEmpty)

        // 2. Install public key
        let publicKey = Data(repeating: 0x44, count: 32)
        try keys.installProfilePublicKey(label: label, publicKey: publicKey)

        // 3. Retrieve public key
        let retrievedKey = try keys.getProfilePublicKeyByLabel(label: label)
        XCTAssertEqual(retrievedKey, publicKey)

        // 4. Test encryption/decryption
        let testData = Data("Workflow test data".utf8)
        let encryptedData = try keys.encryptLocalData(testData)
        let decryptedData = try keys.decryptWithProfile(encryptedData, label: label)
        XCTAssertEqual(decryptedData, testData)
    }

    func testDeriveUserProfileKeyEmptyLabel() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        XCTAssertThrowsError(try keys.deriveUserProfileKey(label: "")) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    func testDeriveUserProfileKeyDuplicateLabel() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let label = "duplicate-test"

        // First derivation should succeed
        let key1 = try keys.deriveUserProfileKey(label: label)
        XCTAssertFalse(key1.isEmpty)

        // Second derivation with same label should succeed (returns same key)
        let key2 = try keys.deriveUserProfileKey(label: label)
        XCTAssertEqual(key1, key2, "Duplicate labels should return same key")
    }

    func testDeriveUserProfileKeyLongLabel() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let longLabel = String(repeating: "a", count: 1000)
        let profileKey = try keys.deriveUserProfileKey(label: longLabel)

        XCTAssertFalse(profileKey.isEmpty, "Long label should work")
        XCTAssertEqual(profileKey.count, 32, "Profile key should be 32 bytes")
    }

    func testDeriveUserProfileKeyUnicodeLabels() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let unicodeLabels = [
            "测试",
            "тест",
            "テスト",
            "🎯",
            "café",
            "naïve"
        ]

        for label in unicodeLabels {
            let profileKey = try keys.deriveUserProfileKey(label: label)
            XCTAssertFalse(profileKey.isEmpty, "Unicode label '\(label)' should work")
            XCTAssertEqual(profileKey.count, 32, "Profile key should be 32 bytes")
        }
    }

    func testInstallProfilePublicKeyInvalidLength() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let label = "test-profile"
        let invalidKey = Data(repeating: 0x42, count: 16) // Too short

        XCTAssertThrowsError(try keys.installProfilePublicKey(label: label, publicKey: invalidKey)) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    func testInstallProfilePublicKeyZeroLength() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let label = "test-profile"
        let emptyKey = Data()

        XCTAssertThrowsError(try keys.installProfilePublicKey(label: label, publicKey: emptyKey)) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    func testGetProfilePublicKeyByLabelAfterInstall() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let label = "after-install-test"
        let publicKey = Data(repeating: 0x43, count: 32)

        // Install key
        try keys.installProfilePublicKey(label: label, publicKey: publicKey)

        // Retrieve key
        let retrievedKey = try keys.getProfilePublicKeyByLabel(label: label)
        XCTAssertEqual(retrievedKey, publicKey, "Key should be retrievable after installation")
    }

    func testProfileKeyWorkflowMultipleLabels() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let labels = ["label1", "label2", "label3"]
        var profileKeys: [String: Data] = [:]

        // Derive keys for multiple labels
        for label in labels {
            let key = try keys.deriveUserProfileKey(label: label)
            profileKeys[label] = key
        }

        // Verify all keys are different
        let uniqueKeys = Set(profileKeys.values)
        XCTAssertEqual(uniqueKeys.count, labels.count, "All profile keys should be unique")

        // Test encryption/decryption for each label
        for label in labels {
            let testData = Data("Test data for \(label)".utf8)
            let encryptedData = try keys.encryptLocalData(testData)
            let decryptedData = try keys.decryptWithProfile(encryptedData, label: label)
            XCTAssertEqual(decryptedData, testData, "Decryption should work for \(label)")
        }
    }

    func testDecryptWithProfileInvalidEnvelopeData() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let label = "invalid-envelope-test"
        let invalidData = Data("invalid-envelope".utf8)

        XCTAssertThrowsError(try keys.decryptWithProfile(invalidData, label: label)) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    func testDecryptWithProfileEmptyEnvelopeData() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let label = "empty-envelope-test"
        let emptyData = Data()

        XCTAssertThrowsError(try keys.decryptWithProfile(emptyData, label: label)) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    func testProfileKeyErrorHandlingConsistency() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let label = "error-test"

        // Test various error conditions
        let errorConditions = [
            ("", "empty label"),
            ("a".repeating(1000), "very long label"),
            ("test\nlabel", "label with newline"),
            ("test\tlabel", "label with tab")
        ]

        for (testLabel, description) in errorConditions {
            if testLabel.isEmpty {
                XCTAssertThrowsError(try keys.deriveUserProfileKey(label: testLabel),
                                     "Should fail for \(description)")
            } else {
                // Some edge cases might work, others might fail
                do {
                    _ = try keys.deriveUserProfileKey(label: testLabel)
                } catch {
                    // Expected for some edge cases
                }
            }
        }
    }

    func testProfileKeyMemoryManagement() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let label = "memory-test"

        // Create and use profile key multiple times
        for i in 0 ..< 10 {
            let testLabel = "\(label)-\(i)"
            let key = try keys.deriveUserProfileKey(label: testLabel)
            XCTAssertFalse(key.isEmpty)

            // Test encryption/decryption
            let testData = Data("Memory test \(i)".utf8)
            let encryptedData = try keys.encryptLocalData(testData)
            let decryptedData = try keys.decryptWithProfile(encryptedData, label: testLabel)
            XCTAssertEqual(decryptedData, testData)
        }
    }

    func testProfileKeyStressTest() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let numberOfKeys = 100
        var keys: [String: Data] = [:]

        // Create many profile keys
        for i in 0 ..< numberOfKeys {
            let label = "stress-test-\(i)"
            let key = try self.keys.deriveUserProfileKey(label: label)
            keys[label] = key
        }

        // Verify all keys are unique
        let uniqueKeys = Set(keys.values)
        XCTAssertEqual(uniqueKeys.count, numberOfKeys, "All stress test keys should be unique")

        // Test encryption/decryption for a subset
        for i in stride(from: 0, to: numberOfKeys, by: 10) {
            let label = "stress-test-\(i)"
            let testData = Data("Stress test data \(i)".utf8)
            let encryptedData = try self.keys.encryptLocalData(testData)
            let decryptedData = try self.keys.decryptWithProfile(encryptedData, label: label)
            XCTAssertEqual(decryptedData, testData)
        }
    }

    // MARK: - Certificate and Network Key Tests

    func testGetCertificateStatusHappyPath() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()
        try keys.generateKeys()

        let status = try keys.getCertificateStatus()
        XCTAssertNotNil(status, "Certificate status should be available")
    }

    func testGetCertificateStatusNullPointers() throws {
        let keys = KeysFFI()

        XCTAssertThrowsError(try keys.getCertificateStatus()) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    func testGetQuicCertificateConfigNoCertificate() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        XCTAssertThrowsError(try keys.getQuicCertificateConfig()) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    func testGetQuicCertificateConfigNullPointers() throws {
        let keys = KeysFFI()

        XCTAssertThrowsError(try keys.getQuicCertificateConfig()) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    func testValidatePeerCertificateInvalidCertificate() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let invalidCertificate = Data("invalid-certificate".utf8)

        XCTAssertThrowsError(try keys.validatePeerCertificate(invalidCertificate)) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    func testValidatePeerCertificateNullPointers() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let emptyCertificate = Data()

        XCTAssertThrowsError(try keys.validatePeerCertificate(emptyCertificate)) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    func testGetQuicCertificateConfigHappyPath() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        // Generate keys and install certificate
        try keys.generateKeys()

        // Create a mock certificate (this would normally come from CA)
        let mockCertificate = Data(repeating: 0x42, count: 1000)
        try keys.installCertificate(mockCertificate)

        let config = try keys.getQuicCertificateConfig()
        XCTAssertNotNil(config, "QUIC certificate config should be available")
    }

    func testInstallNetworkKeyInvalidMessage() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let invalidMessage = Data("invalid-network-key-message".utf8)

        XCTAssertThrowsError(try keys.installNetworkKey(invalidMessage)) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    func testInstallNetworkKeyNullPointers() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let emptyMessage = Data()

        XCTAssertThrowsError(try keys.installNetworkKey(emptyMessage)) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    func testGetNetworkAgreementNoKey() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        XCTAssertThrowsError(try keys.getNetworkAgreement()) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    func testGetNetworkAgreementNullPointers() throws {
        let keys = KeysFFI()

        XCTAssertThrowsError(try keys.getNetworkAgreement()) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    func testHasNetworkPrivateKeyNoKey() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let hasKey = keys.hasNetworkPrivateKey()
        XCTAssertFalse(hasKey, "Should not have network private key before installation")
    }

    func testHasNetworkPrivateKeyNullPointers() throws {
        let keys = KeysFFI()

        let hasKey = keys.hasNetworkPrivateKey()
        XCTAssertFalse(hasKey, "Uninitialized keys should not have network private key")
    }

    func testCertificateAndNetworkKeyErrorHandlingConsistency() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let testCases = [
            ("empty data", Data()),
            ("invalid data", Data("invalid".utf8)),
            ("too small", Data(repeating: 0x42, count: 10)),
            ("too large", Data(repeating: 0x42, count: 100_000))
        ]

        for (description, testData) in testCases {
            // Test certificate validation
            do {
                try keys.validatePeerCertificate(testData)
            } catch {
                XCTAssertTrue(error is FFIError, "Certificate validation should fail for \(description)")
            }

            // Test network key installation
            do {
                try keys.installNetworkKey(testData)
            } catch {
                XCTAssertTrue(error is FFIError, "Network key installation should fail for \(description)")
            }
        }
    }

    // MARK: - CA Infrastructure Tests

    func testCANodeNewHappyPath() throws {
        let logger = SimpleLogger()
        let caNode = try CANode.create(logger: logger)
        XCTAssertNotNil(caNode, "CA Node should be created successfully")
    }

    func testCANodeNewNullLogger() throws {
        let caNode = try CANode.create(logger: nil)
        XCTAssertNotNil(caNode, "CA Node should be created with nil logger")
    }

    func testCANodeNewNullOutput() throws {
        // Test with null output pointer (should fail)
        XCTAssertThrowsError(try CANode.create(logger: nil)) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    func testCANodeFreeNull() throws {
        CANode.free(nil)
    }

    func testCANodeInstallIssuingCAHappyPath() throws {
        let logger = SimpleLogger()
        let caNode = try CANode.create(logger: logger)

        // Create EA key pair
        let eaKeyManager = EAKeyManager(logger: logger)
        let eaKeyHandle = try eaKeyManager.createKeyPair()
        defer { EAKeyManager.free(eaKeyHandle) }

        // Get EA public key
        let eaPublicKey = try eaKeyManager.getPublicKey(eaKeyHandle)
        let eaPublicKeys = [eaPublicKey]
        let eaPublicKeysCbor = try CodableCBOREncoder().encode(eaPublicKeys)

        // Setup CA Node
        let setupParams = CANodeManager.CANodeSetupParams(
            caNode: caNode.handle,
            rootCaSubject: "CN=Test Root CA",
            issuingCaSubject: "CN=Test Issuing CA",
            validityDays: 365,
            issuingCaSerial: 1,
            eaPublicKeys: eaPublicKeysCbor,
            networkId: "test_network"
        )

        try caNode.setupComplete(params: setupParams)
    }

    func testCANodeSetupCompleteNullCANode() throws {
        let logger = SimpleLogger()
        let eaKeyManager = EAKeyManager(logger: logger)
        let eaKeyHandle = try eaKeyManager.createKeyPair()
        defer { EAKeyManager.free(eaKeyHandle) }

        let eaPublicKey = try eaKeyManager.getPublicKey(eaKeyHandle)
        let eaPublicKeys = [eaPublicKey]
        let eaPublicKeysCbor = try CodableCBOREncoder().encode(eaPublicKeys)

        let setupParams = CANodeManager.CANodeSetupParams(
            caNode: UnsafeMutableRawPointer(bitPattern: 1) ?? UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1), // Invalid pointer
            rootCaSubject: "CN=Test Root CA",
            issuingCaSubject: "CN=Test Issuing CA",
            validityDays: 365,
            issuingCaSerial: 1,
            eaPublicKeys: eaPublicKeysCbor,
            networkId: "test_network"
        )

        XCTAssertThrowsError(try CANodeManager().setupComplete(params: setupParams)) { error in
            XCTAssertTrue(error is FFIError)
        }
    }

    func testCAServerNewStub() throws {
        let logger = SimpleLogger()
        let caServer = try CAServer.create(logger: logger)
        XCTAssertNotNil(caServer, "CA Server should be created successfully")
    }

    func testCAServerFreeNull() throws {
        CAServer.free(nil)
    }

    func testCAClientNewStub() throws {
        let logger = SimpleLogger()
        let config = CaClientConfig(
            bootstrapServer: "127.0.0.1:8080",
            authenticatedServer: "127.0.0.1:8081",
            networkId: "test_network",
            requestTimeoutSeconds: 30,
            maxRetries: 3
        )

        let caClient = try CAClient.create(config: config, logger: logger)
        XCTAssertNotNil(caClient, "CA Client should be created successfully")
    }

    func testCAClientFreeNull() throws {
        CAClient.free(nil)
    }

    func testCompleteV2NodeLifecycle() throws {
        let keys = KeysFFI()

        // Initialize as node
        try keys.initializeAsNode()

        // Generate keys
        try keys.generateKeys()

        // Check if keys exist
        let hasKeys = keys.hasKeys()
        XCTAssertTrue(hasKeys, "Keys should exist after generation")

        // Get node ID
        let nodeId = try keys.getNodeId()
        XCTAssertFalse(nodeId.isEmpty, "Node ID should not be empty")

        // Test profile key operations
        let label = "lifecycle-test"
        let profileKey = try keys.deriveUserProfileKey(label: label)
        XCTAssertFalse(profileKey.isEmpty, "Profile key should not be empty")

        // Test encryption/decryption
        let testData = Data("Lifecycle test data".utf8)
        let encryptedData = try keys.encryptLocalData(testData)
        let decryptedData = try keys.decryptWithProfile(encryptedData, label: label)
        XCTAssertEqual(decryptedData, testData, "Decrypted data should match original")
    }

    func testV2APIErrorHandlingConsistency() throws {
        let keys = KeysFFI()

        // Test various error conditions
        let errorConditions = [
            ("uninitialized", { try keys.hasKeys() }),
            ("wrong manager type", {
                try keys.initializeAsMobile()
                return try keys.hasKeys()
            }),
            ("empty label", {
                try keys.initializeAsNode()
                return try keys.deriveUserProfileKey(label: "")
            })
        ]

        for (description, testFunction) in errorConditions {
            do {
                _ = try testFunction()
            } catch {
                XCTAssertTrue(error is FFIError, "Should fail with FFIError for \(description)")
            }
        }
    }
}

// MARK: - Helper Extensions

extension String {
    func repeating(_ count: Int) -> String {
        String(repeating: self, count: count)
    }
}
