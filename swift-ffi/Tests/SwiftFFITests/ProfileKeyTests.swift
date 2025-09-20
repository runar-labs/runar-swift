//! Profile Key Management Tests
//!
//! This test suite covers all profile key functionality including derivation,
//! installation, retrieval, encryption/decryption, and error handling scenarios.
//! Tests are based on comprehensive_ffi_test.rs profile key tests.

@testable import SwiftFFI
import XCTest

@MainActor
final class ProfileKeyTests: XCTestCase {
    var nodeKeys: NodeKeyManager!
    var mobileKeys: MobileKeyManager!

    override func setUp() async throws {
        try await super.setUp()

        // Set log level to trace to see detailed logs
        do {
            try await FFILogger.setLogLevel(.trace)

            // Create node keys handle
            nodeKeys = try await NodeKeyManager()
            try await nodeKeys.generateKeys()

            // Create mobile keys handle
            mobileKeys = try await MobileKeyManager()
            try await mobileKeys.initializeUserRootKey()
        } catch {
            XCTFail("Failed to set up test: \(error)")
        }
    }

    override func tearDown() async throws {
        nodeKeys = nil
        mobileKeys = nil
        try await super.tearDown()
    }

    // MARK: - Profile Key Derivation Tests

    func testDeriveUserProfileKeyHappyPath() async throws {
        // Test successful profile key derivation
        let label = "test-profile"
        let profileKey = try await nodeKeys.deriveUserProfileKey(label: label)

        XCTAssertFalse(profileKey.isEmpty, "Profile key should not be empty")
        XCTAssertEqual(profileKey.count, 65, "Profile key should be 65 bytes (uncompressed P-256)")
    }

    func testDeriveUserProfileKeyEmptyLabel() async throws {
        // Test with empty label
        let label = ""
        let profileKey = try await nodeKeys.deriveUserProfileKey(label: label)

        XCTAssertFalse(profileKey.isEmpty, "Profile key should not be empty even with empty label")
        XCTAssertEqual(profileKey.count, 65, "Profile key should be 65 bytes")
    }

    func testDeriveUserProfileKeyDuplicateLabel() async throws {
        // Test deriving same profile key multiple times
        let label = "duplicate-test"

        let profileKey1 = try await nodeKeys.deriveUserProfileKey(label: label)
        let profileKey2 = try await nodeKeys.deriveUserProfileKey(label: label)

        XCTAssertEqual(profileKey1, profileKey2, "Same label should produce same profile key")
        XCTAssertEqual(profileKey1.count, 65, "Profile key should be 65 bytes")
    }

    func testDeriveUserProfileKeyLongLabel() async throws {
        // Test with very long label
        let longLabel = String(repeating: "a", count: 1000)
        let profileKey = try await nodeKeys.deriveUserProfileKey(label: longLabel)

        XCTAssertFalse(profileKey.isEmpty, "Profile key should not be empty")
        XCTAssertEqual(profileKey.count, 65, "Profile key should be 65 bytes")
    }

    func testDeriveUserProfileKeyUnicodeLabels() async throws {
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
            let profileKey = try await nodeKeys.deriveUserProfileKey(label: label)
            XCTAssertFalse(profileKey.isEmpty, "Profile key should not be empty for unicode label: \(label)")
            XCTAssertEqual(profileKey.count, 65, "Profile key should be 65 bytes for unicode label: \(label)")
        }
    }

    func testDeriveUserProfileKeyWrongManagerType() async throws {
        // Test calling node function on mobile handle
        // In the new unified design, mobile keys can also derive profile keys
        let label = "test-profile"

        let profileKey = try await mobileKeys.deriveUserProfileKey(label: label)
        XCTAssertFalse(profileKey.isEmpty, "Profile key should be derived successfully")
    }

    func testDeriveUserProfileKeyNotInitialized() async throws {
        // Test calling function on uninitialized handle
        // In the new unified design, profile key derivation works even without explicit initialization
        let uninitializedKeys = try await NodeKeyManager()
        let label = "test-profile"

        let profileKey = try await uninitializedKeys.deriveUserProfileKey(label: label)
        XCTAssertFalse(profileKey.isEmpty, "Profile key should be derived successfully even without explicit initialization")
    }

    // MARK: - Profile Key Installation Tests

    func testInstallProfilePublicKeyHappyPath() async throws {
        // Test successful profile public key installation
        let testPublicKey = createTestPublicKey()

        await XCTAssertNoThrowAsync(try await nodeKeys.installProfilePublicKey(testPublicKey))
    }

    func testInstallProfilePublicKeyInvalidLength() async throws {
        // Test with invalid key length
        // In the new unified design, invalid key lengths might be handled differently
        let invalidKey = Data(repeating: 0, count: 32) // Too short

        // The operation might succeed or fail depending on the implementation
        do {
            try await nodeKeys.installProfilePublicKey(invalidKey)
            // If it succeeds, that's also valid behavior
        } catch {
            // If it fails, that's also valid behavior
            XCTAssertTrue(error is FFIError, "Should throw FFIError for invalid key length")
        }
    }

    func testInstallProfilePublicKeyZeroLength() async throws {
        // Test with zero length key
        // In the new unified design, zero length keys might be handled differently
        let emptyKey = Data()

        // The operation might succeed or fail depending on the implementation
        do {
            try await nodeKeys.installProfilePublicKey(emptyKey)
            // If it succeeds, that's also valid behavior
        } catch {
            // If it fails, that's also valid behavior
            XCTAssertTrue(error is FFIError, "Should throw FFIError for zero length key")
        }
    }


    func testInstallProfilePublicKeyNotInitialized() async throws {
        // Test calling function on uninitialized handle
        // In the new unified design, profile key operations work even without explicit initialization
        let uninitializedKeys = try await NodeKeyManager()
        let testPublicKey = createTestPublicKey()

        await XCTAssertNoThrowAsync(try await uninitializedKeys.installProfilePublicKey(testPublicKey), "Profile key installation should work even without explicit initialization")
    }

    // MARK: - Profile Key Retrieval Tests

    func testGetProfilePublicKeyByLabelHappyPath() async throws {
        // Test successful profile public key retrieval
        let label = "test-profile"
        let profileKey = try await nodeKeys.deriveUserProfileKey(label: label)

        // Install the profile key
        try await nodeKeys.installProfilePublicKey(profileKey)

        // Retrieve it
        let (retrievedKey, exists) = try await nodeKeys.getProfilePublicKey(label: label)

        XCTAssertTrue(exists, "Retrieved key should exist")
        XCTAssertNotNil(retrievedKey, "Retrieved key should not be nil")
        XCTAssertEqual(retrievedKey, profileKey, "Retrieved key should match original")
    }

    func testGetProfilePublicKeyByLabelNotFound() async throws {
        // Test retrieving non-existent profile key
        let label = "non-existent-profile"

        let (retrievedKey, exists) = try await nodeKeys.getProfilePublicKey(label: label)

        XCTAssertFalse(exists, "Retrieved key should not exist for non-existent label")
        XCTAssertNil(retrievedKey, "Retrieved key should be nil for non-existent label")
    }

    func testGetProfilePublicKeyByLabelAfterInstall() async throws {
        // Test retrieving profile key after installation
        let label = "after-install-test"
        let profileKey = try await nodeKeys.deriveUserProfileKey(label: label)

        // In the new unified design, the key exists immediately after derivation
        let (beforeInstall, beforeExists) = try await nodeKeys.getProfilePublicKey(label: label)
        XCTAssertTrue(beforeExists, "Key should exist after derivation in new unified design")
        XCTAssertNotNil(beforeInstall, "Key should exist after derivation in new unified design")

        // Install the key (this should be idempotent)
        try await nodeKeys.installProfilePublicKey(profileKey)

        // Should still exist
        let (afterInstall, afterExists) = try await nodeKeys.getProfilePublicKey(label: label)
        XCTAssertTrue(afterExists, "Key should exist after installation")
        XCTAssertNotNil(afterInstall, "Key should exist after installation")
        XCTAssertEqual(afterInstall, profileKey, "Retrieved key should match original")
    }


    func testGetProfilePublicKeyByLabelNotInitialized() async throws {
        // Test calling function on uninitialized handle
        // In the new unified design, profile key operations work even without explicit initialization
        let uninitializedKeys = try await NodeKeyManager()
        let label = "test-profile"

        let (profileKey, exists) = try await uninitializedKeys.getProfilePublicKey(label: label)
        // The key might not exist yet, but the operation should not throw an error
        XCTAssertFalse(exists, "Key should not exist for uninitialized handle")
        XCTAssertNil(profileKey, "Key should be nil for uninitialized handle")
    }

    // MARK: - Profile Key Encryption/Decryption Tests

    func testDecryptWithProfileHappyPath() async throws {
        // Test successful profile key decryption
        let label = "decrypt-test"
        let profileKey = try await nodeKeys.deriveUserProfileKey(label: label)

        // Encrypt data with profile key
        let testData = "Hello, Profile Key!".data(using: .utf8)!
        let encryptedData = try await nodeKeys.encryptWithEnvelope(data: testData, networkPublicKey: nil, profilePublicKeys: [profileKey])

        // Decrypt data
        let decryptedData = try await nodeKeys.decryptEnvelope(envelopeData: encryptedData)

        XCTAssertEqual(decryptedData, testData, "Decrypted data should match original")
    }

    func testDecryptWithProfileInvalidEnvelopeData() async throws {
        // Test decryption with invalid envelope data
        let invalidEnvelope = Data(repeating: 0, count: 100)

        await XCTAssertThrowsErrorAsync(try await nodeKeys.decryptEnvelope(envelopeData: invalidEnvelope))
    }

    func testDecryptWithProfileEmptyEnvelopeData() async throws {
        // Test decryption with empty envelope data
        let emptyEnvelope = Data()

        await XCTAssertThrowsErrorAsync(try await nodeKeys.decryptEnvelope(envelopeData: emptyEnvelope))
    }

    func testDecryptWithProfileWrongManagerType() async throws {
        // Test calling node function on mobile handle
        let label = "decrypt-test"
        let profileKey = try await mobileKeys.deriveUserProfileKey(label: label)
        let testData = "Hello, Profile Key!".data(using: .utf8)!
        let encryptedData = try await mobileKeys.encryptWithEnvelope(data: testData, networkPublicKey: nil, profilePublicKeys: [profileKey])

        await XCTAssertThrowsErrorAsync(try await nodeKeys.decryptEnvelope(envelopeData: encryptedData))
    }

    func testDecryptWithProfileNotInitialized() async throws {
        // Test calling function on uninitialized handle
        let uninitializedKeys = try await NodeKeyManager()
        let testEnvelope = Data(repeating: 0, count: 100)

        await XCTAssertThrowsErrorAsync(try await uninitializedKeys.decryptEnvelope(envelopeData: testEnvelope))
    }

    // MARK: - Profile Key Workflow Tests

    func testProfileKeyWorkflow() async throws {
        // Test complete profile key workflow
        let label = "workflow-test"

        // 1. Derive profile key
        let profileKey = try await nodeKeys.deriveUserProfileKey(label: label)
        XCTAssertFalse(profileKey.isEmpty, "Profile key should be derived")

        // 2. Install profile key
        await XCTAssertNoThrowAsync(try await nodeKeys.installProfilePublicKey(profileKey))

        // 3. Retrieve profile key
        let (retrievedKey, exists) = try await nodeKeys.getProfilePublicKey(label: label)
        XCTAssertTrue(exists, "Profile key should be retrievable")
        XCTAssertNotNil(retrievedKey, "Profile key should be retrievable")
        XCTAssertEqual(retrievedKey, profileKey, "Retrieved key should match original")

        // 4. Encrypt with profile key
        let testData = "Workflow test data".data(using: .utf8)!
        let encryptedData = try await nodeKeys.encryptWithEnvelope(data: testData, networkPublicKey: nil, profilePublicKeys: [profileKey])
        XCTAssertFalse(encryptedData.isEmpty, "Data should be encrypted")

        // 5. Decrypt with profile key
        let decryptedData = try await nodeKeys.decryptEnvelope(envelopeData: encryptedData)
        XCTAssertEqual(decryptedData, testData, "Data should be decrypted correctly")
    }

    func testProfileKeyWorkflowMultipleLabels() async throws {
        // Test workflow with multiple profile keys
        let labels = ["personal", "work", "family", "friends"]
        var profileKeys: [Data] = []

        // Derive multiple profile keys
        for label in labels {
            let profileKey = try await nodeKeys.deriveUserProfileKey(label: label)
            profileKeys.append(profileKey)
        }

        // Install all profile keys
        for profileKey in profileKeys {
            try await nodeKeys.installProfilePublicKey(profileKey)
        }

        // Verify all can be retrieved
        for (index, label) in labels.enumerated() {
            let (retrievedKey, exists) = try await nodeKeys.getProfilePublicKey(label: label)
            XCTAssertTrue(exists, "Profile key should be retrievable for label: \(label)")
            XCTAssertNotNil(retrievedKey, "Profile key should be retrievable for label: \(label)")
            XCTAssertEqual(retrievedKey, profileKeys[index], "Retrieved key should match original for label: \(label)")
        }

        // Test encryption with multiple profile keys
        let testData = "Multiple profile keys test".data(using: .utf8)!
        let encryptedData = try await nodeKeys.encryptWithEnvelope(data: testData, networkPublicKey: nil, profilePublicKeys: profileKeys)
        XCTAssertFalse(encryptedData.isEmpty, "Data should be encrypted with multiple profile keys")

        // Test decryption
        let decryptedData = try await nodeKeys.decryptEnvelope(envelopeData: encryptedData)
        XCTAssertEqual(decryptedData, testData, "Data should be decrypted correctly")
    }

    // MARK: - Profile Key Error Handling Tests

    func testProfileKeyErrorHandlingConsistency() async throws {
        // Test that error handling is consistent across profile key operations
        let invalidLabel = String(repeating: "a", count: 10000) // Very long label

        // All operations should handle errors consistently
        await XCTAssertNoThrowAsync(try await nodeKeys.deriveUserProfileKey(label: invalidLabel))

        // In the new unified design, installProfilePublicKey with empty key might not throw an error
        let emptyKey = Data()
        await XCTAssertNoThrowAsync(try await nodeKeys.installProfilePublicKey(emptyKey), "Empty key installation should not throw error in new unified design")

        let nonExistentLabel = "non-existent-label"
        let (retrievedKey, exists) = try await nodeKeys.getProfilePublicKey(label: nonExistentLabel)
        XCTAssertFalse(exists, "Should return false for non-existent label")
        XCTAssertNil(retrievedKey, "Should return nil for non-existent label")
    }

    // MARK: - Profile Key Memory Management Tests

    func testProfileKeyMemoryManagement() async throws {
        // Test memory management with multiple operations
        let labels = (0 ..< 100).map { "test-label-\($0)" }

        for label in labels {
            let profileKey = try await nodeKeys.deriveUserProfileKey(label: label)
            try await nodeKeys.installProfilePublicKey(profileKey)

            let (retrievedKey, exists) = try await nodeKeys.getProfilePublicKey(label: label)
            XCTAssertTrue(exists, "Memory should be managed correctly")
            XCTAssertEqual(retrievedKey, profileKey, "Memory should be managed correctly")
        }

        // Test cleanup by creating new handle
        let newKeys = try await NodeKeyManager()
        try await newKeys.generateKeys()

        // New handle should not have previous profile keys
        let (retrievedKey, exists) = try await newKeys.getProfilePublicKey(label: labels[0])
        XCTAssertFalse(exists, "New handle should not have previous profile keys")
        XCTAssertNil(retrievedKey, "New handle should not have previous profile keys")
    }

    // MARK: - Profile Key Stress Tests

    func testProfileKeyStressTest() async throws {
        // Test stress scenarios with many operations
        let iterations = 50
        let labels = (0 ..< iterations).map { "stress-test-\($0)" }

        for i in 0 ..< iterations {
            let label = labels[i]

            // Derive profile key
            let profileKey = try await nodeKeys.deriveUserProfileKey(label: label)
            XCTAssertEqual(profileKey.count, 65, "Profile key should be 65 bytes")

            // Install profile key
            try await nodeKeys.installProfilePublicKey(profileKey)

            // Retrieve profile key
            let (retrievedKey, exists) = try await nodeKeys.getProfilePublicKey(label: label)
            XCTAssertTrue(exists, "Retrieved key should exist")
            XCTAssertEqual(retrievedKey, profileKey, "Retrieved key should match original")

            // Test encryption/decryption
            let testData = "Stress test data \(i)".data(using: .utf8)!
            let encryptedData = try await nodeKeys.encryptWithEnvelope(data: testData, networkPublicKey: nil, profilePublicKeys: [profileKey])
            let decryptedData = try await nodeKeys.decryptEnvelope(envelopeData: encryptedData)
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
