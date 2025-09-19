//! Profile Key Management Tests
//!
//! This test suite covers all profile key functionality including derivation,
//! installation, retrieval, encryption/decryption, and error handling scenarios.
//! Tests are based on comprehensive_ffi_test.rs profile key tests.

@testable import SwiftFFI
import XCTest

final class ProfileKeyTests: XCTestCase {
    var nodeKeys: NodeKeyManager!
    var mobileKeys: MobileKeyManager!

    override func setUp() {
        super.setUp()

        // Set log level to trace to see detailed logs
        do {
            try FFILogger.setLogLevel(.trace)

            // Create node keys handle
            nodeKeys = try NodeKeyManager()
            try nodeKeys.generateKeys()

            // Create mobile keys handle
            mobileKeys = try MobileKeyManager()
            try mobileKeys.initializeUserRootKey()
        } catch {
            XCTFail("Failed to set up test: \(error)")
        }
    }

    override func tearDown() {
        nodeKeys = nil
        mobileKeys = nil
        super.tearDown()
    }

    // MARK: - Profile Key Derivation Tests

    func testDeriveUserProfileKeyHappyPath() throws {
        // Test successful profile key derivation
        let label = "test-profile"
        let profileKey = try nodeKeys.deriveUserProfileKey(label: label)

        XCTAssertFalse(profileKey.isEmpty, "Profile key should not be empty")
        XCTAssertEqual(profileKey.count, 65, "Profile key should be 65 bytes (uncompressed P-256)")
    }

    func testDeriveUserProfileKeyEmptyLabel() throws {
        // Test with empty label
        let label = ""
        let profileKey = try nodeKeys.deriveUserProfileKey(label: label)

        XCTAssertFalse(profileKey.isEmpty, "Profile key should not be empty even with empty label")
        XCTAssertEqual(profileKey.count, 65, "Profile key should be 65 bytes")
    }

    func testDeriveUserProfileKeyDuplicateLabel() throws {
        // Test deriving same profile key multiple times
        let label = "duplicate-test"

        let profileKey1 = try nodeKeys.deriveUserProfileKey(label: label)
        let profileKey2 = try nodeKeys.deriveUserProfileKey(label: label)

        XCTAssertEqual(profileKey1, profileKey2, "Same label should produce same profile key")
        XCTAssertEqual(profileKey1.count, 65, "Profile key should be 65 bytes")
    }

    func testDeriveUserProfileKeyLongLabel() throws {
        // Test with very long label
        let longLabel = String(repeating: "a", count: 1000)
        let profileKey = try nodeKeys.deriveUserProfileKey(label: longLabel)

        XCTAssertFalse(profileKey.isEmpty, "Profile key should not be empty")
        XCTAssertEqual(profileKey.count, 65, "Profile key should be 65 bytes")
    }

    func testDeriveUserProfileKeyUnicodeLabels() throws {
        // Test with unicode labels
        let unicodeLabels = [
            "测试",
            "тест",
            "テスト",
            "🎯",
            "café",
            "naïve",
        ]

        for label in unicodeLabels {
            let profileKey = try nodeKeys.deriveUserProfileKey(label: label)
            XCTAssertFalse(profileKey.isEmpty, "Profile key should not be empty for unicode label: \(label)")
            XCTAssertEqual(profileKey.count, 65, "Profile key should be 65 bytes for unicode label: \(label)")
        }
    }

    func testDeriveUserProfileKeyWrongManagerType() throws {
        // Test calling node function on mobile handle
        let label = "test-profile"

        XCTAssertThrowsError(try mobileKeys.deriveUserProfileKey(label: label)) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError")
        }
    }

    func testDeriveUserProfileKeyNotInitialized() throws {
        // Test calling function on uninitialized handle
        let uninitializedKeys = try NodeKeyManager()
        let label = "test-profile"

        XCTAssertThrowsError(try uninitializedKeys.deriveUserProfileKey(label: label)) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError")
        }
    }

    // MARK: - Profile Key Installation Tests

    func testInstallProfilePublicKeyHappyPath() throws {
        // Test successful profile public key installation
        let testPublicKey = createTestPublicKey()

        XCTAssertNoThrow(try nodeKeys.installProfilePublicKey(testPublicKey))
    }

    func testInstallProfilePublicKeyInvalidLength() throws {
        // Test with invalid key length
        let invalidKey = Data(repeating: 0, count: 32) // Too short

        XCTAssertThrowsError(try nodeKeys.installProfilePublicKey(invalidKey)) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError for invalid key length")
        }
    }

    func testInstallProfilePublicKeyZeroLength() throws {
        // Test with zero length key
        let emptyKey = Data()

        XCTAssertThrowsError(try nodeKeys.installProfilePublicKey(emptyKey)) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError for zero length key")
        }
    }

    func testInstallProfilePublicKeyWrongManagerType() throws {
        throw XCTSkip("Profile key management not supported on mobile keys in new unified design")
    }

    func testInstallProfilePublicKeyNotInitialized() throws {
        // Test calling function on uninitialized handle
        let uninitializedKeys = try NodeKeyManager()
        let testPublicKey = createTestPublicKey()

        XCTAssertThrowsError(try uninitializedKeys.installProfilePublicKey(testPublicKey)) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError")
        }
    }

    // MARK: - Profile Key Retrieval Tests

    func testGetProfilePublicKeyByLabelHappyPath() throws {
        // Test successful profile public key retrieval
        let label = "test-profile"
        let profileKey = try nodeKeys.deriveUserProfileKey(label: label)

        // Install the profile key
        try nodeKeys.installProfilePublicKey(profileKey)

        // Retrieve it
        let (retrievedKey, exists) = try nodeKeys.getProfilePublicKey(label: label)

        XCTAssertTrue(exists, "Retrieved key should exist")
        XCTAssertNotNil(retrievedKey, "Retrieved key should not be nil")
        XCTAssertEqual(retrievedKey, profileKey, "Retrieved key should match original")
    }

    func testGetProfilePublicKeyByLabelNotFound() throws {
        // Test retrieving non-existent profile key
        let label = "non-existent-profile"

        let (retrievedKey, exists) = try nodeKeys.getProfilePublicKey(label: label)

        XCTAssertFalse(exists, "Retrieved key should not exist for non-existent label")
        XCTAssertNil(retrievedKey, "Retrieved key should be nil for non-existent label")
    }

    func testGetProfilePublicKeyByLabelAfterInstall() throws {
        // Test retrieving profile key after installation
        let label = "after-install-test"
        let profileKey = try nodeKeys.deriveUserProfileKey(label: label)

        // Initially should not exist
        let (beforeInstall, beforeExists) = try nodeKeys.getProfilePublicKey(label: label)
        XCTAssertFalse(beforeExists, "Key should not exist before installation")
        XCTAssertNil(beforeInstall, "Key should not exist before installation")

        // Install the key
        try nodeKeys.installProfilePublicKey(profileKey)

        // Now should exist
        let (afterInstall, afterExists) = try nodeKeys.getProfilePublicKey(label: label)
        XCTAssertTrue(afterExists, "Key should exist after installation")
        XCTAssertNotNil(afterInstall, "Key should exist after installation")
        XCTAssertEqual(afterInstall, profileKey, "Retrieved key should match original")
    }

    func testGetProfilePublicKeyByLabelWrongManagerType() throws {
        throw XCTSkip("Profile key management not supported on mobile keys in new unified design")
    }

    func testGetProfilePublicKeyByLabelNotInitialized() throws {
        // Test calling function on uninitialized handle
        let uninitializedKeys = try NodeKeyManager()
        let label = "test-profile"

        XCTAssertThrowsError(try uninitializedKeys.getProfilePublicKey(label: label)) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError")
        }
    }

    // MARK: - Profile Key Encryption/Decryption Tests

    func testDecryptWithProfileHappyPath() throws {
        // Test successful profile key decryption
        let label = "decrypt-test"
        let profileKey = try nodeKeys.deriveUserProfileKey(label: label)

        // Encrypt data with profile key
        let testData = "Hello, Profile Key!".data(using: .utf8)!
        let encryptedData = try nodeKeys.encryptWithEnvelope(data: testData, networkPublicKey: nil, profilePublicKeys: [profileKey])

        // Decrypt data
        let decryptedData = try nodeKeys.decryptEnvelope(envelopeData: encryptedData)

        XCTAssertEqual(decryptedData, testData, "Decrypted data should match original")
    }

    func testDecryptWithProfileInvalidEnvelopeData() throws {
        // Test decryption with invalid envelope data
        let invalidEnvelope = Data(repeating: 0, count: 100)

        XCTAssertThrowsError(try nodeKeys.decryptEnvelope(envelopeData: invalidEnvelope)) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError for invalid envelope")
        }
    }

    func testDecryptWithProfileEmptyEnvelopeData() throws {
        // Test decryption with empty envelope data
        let emptyEnvelope = Data()

        XCTAssertThrowsError(try nodeKeys.decryptEnvelope(envelopeData: emptyEnvelope)) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError for empty envelope")
        }
    }

    func testDecryptWithProfileWrongManagerType() throws {
        // Test calling node function on mobile handle
        let label = "decrypt-test"
        let profileKey = try mobileKeys.deriveUserProfileKey(label: label)
        let testData = "Hello, Profile Key!".data(using: .utf8)!
        let encryptedData = try mobileKeys.encryptWithEnvelope(data: testData, networkPublicKey: nil, profilePublicKeys: [profileKey])

        XCTAssertThrowsError(try nodeKeys.decryptEnvelope(envelopeData: encryptedData)) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError")
        }
    }

    func testDecryptWithProfileNotInitialized() throws {
        // Test calling function on uninitialized handle
        let uninitializedKeys = try NodeKeyManager()
        let testEnvelope = Data(repeating: 0, count: 100)

        XCTAssertThrowsError(try uninitializedKeys.decryptEnvelope(envelopeData: testEnvelope)) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError")
        }
    }

    // MARK: - Profile Key Workflow Tests

    func testProfileKeyWorkflow() throws {
        // Test complete profile key workflow
        let label = "workflow-test"

        // 1. Derive profile key
        let profileKey = try nodeKeys.deriveUserProfileKey(label: label)
        XCTAssertFalse(profileKey.isEmpty, "Profile key should be derived")

        // 2. Install profile key
        XCTAssertNoThrow(try nodeKeys.installProfilePublicKey(profileKey))

        // 3. Retrieve profile key
        let (retrievedKey, exists) = try nodeKeys.getProfilePublicKey(label: label)
        XCTAssertTrue(exists, "Profile key should be retrievable")
        XCTAssertNotNil(retrievedKey, "Profile key should be retrievable")
        XCTAssertEqual(retrievedKey, profileKey, "Retrieved key should match original")

        // 4. Encrypt with profile key
        let testData = "Workflow test data".data(using: .utf8)!
        let encryptedData = try nodeKeys.encryptWithEnvelope(data: testData, networkPublicKey: nil, profilePublicKeys: [profileKey])
        XCTAssertFalse(encryptedData.isEmpty, "Data should be encrypted")

        // 5. Decrypt with profile key
        let decryptedData = try nodeKeys.decryptEnvelope(envelopeData: encryptedData)
        XCTAssertEqual(decryptedData, testData, "Data should be decrypted correctly")
    }

    func testProfileKeyWorkflowMultipleLabels() throws {
        // Test workflow with multiple profile keys
        let labels = ["personal", "work", "family", "friends"]
        var profileKeys: [Data] = []

        // Derive multiple profile keys
        for label in labels {
            let profileKey = try nodeKeys.deriveUserProfileKey(label: label)
            profileKeys.append(profileKey)
        }

        // Install all profile keys
        for profileKey in profileKeys {
            try nodeKeys.installProfilePublicKey(profileKey)
        }

        // Verify all can be retrieved
        for (index, label) in labels.enumerated() {
            let (retrievedKey, exists) = try nodeKeys.getProfilePublicKey(label: label)
            XCTAssertTrue(exists, "Profile key should be retrievable for label: \(label)")
            XCTAssertNotNil(retrievedKey, "Profile key should be retrievable for label: \(label)")
            XCTAssertEqual(retrievedKey, profileKeys[index], "Retrieved key should match original for label: \(label)")
        }

        // Test encryption with multiple profile keys
        let testData = "Multiple profile keys test".data(using: .utf8)!
        let encryptedData = try nodeKeys.encryptWithEnvelope(data: testData, networkPublicKey: nil, profilePublicKeys: profileKeys)
        XCTAssertFalse(encryptedData.isEmpty, "Data should be encrypted with multiple profile keys")

        // Test decryption
        let decryptedData = try nodeKeys.decryptEnvelope(envelopeData: encryptedData)
        XCTAssertEqual(decryptedData, testData, "Data should be decrypted correctly")
    }

    // MARK: - Profile Key Error Handling Tests

    func testProfileKeyErrorHandlingConsistency() throws {
        // Test that error handling is consistent across profile key operations
        let invalidLabel = String(repeating: "a", count: 10000) // Very long label

        // All operations should handle errors consistently
        XCTAssertNoThrow(try nodeKeys.deriveUserProfileKey(label: invalidLabel))

        let emptyKey = Data()
        XCTAssertThrowsError(try nodeKeys.installProfilePublicKey(emptyKey)) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError for empty key")
        }

        let nonExistentLabel = "non-existent-label"
        let (retrievedKey, exists) = try nodeKeys.getProfilePublicKey(label: nonExistentLabel)
        XCTAssertFalse(exists, "Should return false for non-existent label")
        XCTAssertTrue(retrievedKey.isEmpty, "Should return empty data for non-existent label")
    }

    // MARK: - Profile Key Memory Management Tests

    func testProfileKeyMemoryManagement() throws {
        // Test memory management with multiple operations
        let labels = (0 ..< 100).map { "test-label-\($0)" }

        for label in labels {
            let profileKey = try nodeKeys.deriveUserProfileKey(label: label)
            try nodeKeys.installProfilePublicKey(profileKey)

            let (retrievedKey, exists) = try nodeKeys.getProfilePublicKey(label: label)
            XCTAssertTrue(exists, "Memory should be managed correctly")
            XCTAssertEqual(retrievedKey, profileKey, "Memory should be managed correctly")
        }

        // Test cleanup by creating new handle
        let newKeys = try NodeKeyManager()
        try newKeys.generateKeys()

        // New handle should not have previous profile keys
        let (retrievedKey, exists) = try newKeys.getProfilePublicKey(label: labels[0])
        XCTAssertFalse(exists, "New handle should not have previous profile keys")
        XCTAssertTrue(retrievedKey.isEmpty, "New handle should not have previous profile keys")
    }

    // MARK: - Profile Key Stress Tests

    func testProfileKeyStressTest() throws {
        // Test stress scenarios with many operations
        let iterations = 50
        let labels = (0 ..< iterations).map { "stress-test-\($0)" }

        for i in 0 ..< iterations {
            let label = labels[i]

            // Derive profile key
            let profileKey = try nodeKeys.deriveUserProfileKey(label: label)
            XCTAssertEqual(profileKey.count, 65, "Profile key should be 65 bytes")

            // Install profile key
            try nodeKeys.installProfilePublicKey(profileKey)

            // Retrieve profile key
            let (retrievedKey, exists) = try nodeKeys.getProfilePublicKey(label: label)
            XCTAssertTrue(exists, "Retrieved key should exist")
            XCTAssertEqual(retrievedKey, profileKey, "Retrieved key should match original")

            // Test encryption/decryption
            let testData = "Stress test data \(i)".data(using: .utf8)!
            let encryptedData = try nodeKeys.encryptWithEnvelope(data: testData, networkPublicKey: nil, profilePublicKeys: [profileKey])
            let decryptedData = try nodeKeys.decryptEnvelope(envelopeData: encryptedData)
            XCTAssertEqual(decryptedData, testData, "Encryption/decryption should work correctly")
        }
    }

    // MARK: - Helper Methods

    private func createTestPublicKey() -> Data {
        // Create a test public key (65 bytes for uncompressed P-256)
        var testPublicKey = Data(count: 65)
        testPublicKey[0] = 0x04 // Uncompressed point marker
        // Fill with test data (not a real key, just for testing)
        for i in 1 ..< 65 {
            testPublicKey[i] = UInt8(i % 256)
        }
        return testPublicKey
    }
}
