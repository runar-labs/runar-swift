@testable import RunarFFI
import XCTest

/// Cross-Platform Tests
///
/// Tests for core functionality that should work consistently across platforms.
/// Mirrors the cross_platform_tests.rs from Rust.
final class CrossPlatformTests: XCTestCase {
    // MARK: - Core Handle Tests

    func testCoreHandleCreationAndCleanup() throws {
        let keys = KeysFFI()
        XCTAssertNotNil(keys, "Core handle should be created successfully")

        // Handle should be automatically cleaned up when deallocated
        // This is implicit in Swift's ARC
    }

    func testCoreInitializationFlow() throws {
        let keys = KeysFFI()

        // Test mobile initialization flow
        XCTAssertNoThrow(try keys.initializeAsMobile(), "Mobile initialization should succeed")

        // Test that we can perform mobile operations
        XCTAssertNoThrow(try keys.mobileInitializeUserRootKey(), "Mobile operations should work after init")

        let publicKey = try keys.mobileGetUserPublicKey()
        XCTAssertFalse(publicKey.isEmpty, "Should be able to get user public key")
    }

    func testCoreNodeInitializationFlow() throws {
        let keys = KeysFFI()

        // Test node initialization flow
        XCTAssertNoThrow(try keys.initializeAsNode(), "Node initialization should succeed")

        // Test that we can perform node operations
        XCTAssertNoThrow(try keys.nodeGetPublicKey(), "Node operations should work after init")
        XCTAssertNoThrow(try keys.nodeGetAgreementPublicKey(), "Node operations should work after init")
        XCTAssertNoThrow(try keys.nodeGetNodeId(), "Node operations should work after init")

        let publicKey = try keys.nodeGetPublicKey()
        XCTAssertFalse(publicKey.isEmpty, "Should be able to get node public key")

        let agreementKey = try keys.nodeGetAgreementPublicKey()
        XCTAssertFalse(agreementKey.isEmpty, "Should be able to get node agreement public key")

        let nodeId = try keys.nodeGetNodeId()
        XCTAssertFalse(nodeId.isEmpty, "Should be able to get node ID")
    }

    // MARK: - Error Handling Tests

    func testCoreErrorHandlingConsistency() throws {
        let keys = KeysFFI()

        // Test that uninitialized keys throw consistent errors
        XCTAssertThrowsError(try keys.mobileInitializeUserRootKey()) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError consistently")
        }

        XCTAssertThrowsError(try keys.nodeGetPublicKey()) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError consistently")
        }
    }

    func testCoreManagerTypeIsolation() throws {
        let mobileKeys = KeysFFI()
        let nodeKeys = KeysFFI()

        try mobileKeys.initializeAsMobile()
        try nodeKeys.initializeAsNode()

        // Mobile functions should work on mobile keys
        XCTAssertNoThrow(try mobileKeys.mobileInitializeUserRootKey(), "Mobile functions should work on mobile keys")

        // Node functions should work on node keys
        XCTAssertNoThrow(try nodeKeys.nodeGetPublicKey(), "Node functions should work on node keys")

        // Mobile functions should fail on node keys
        XCTAssertThrowsError(try nodeKeys.mobileInitializeUserRootKey()) { error in
            XCTAssertTrue(error is FFIError, "Mobile functions should fail on node keys")
        }

        // Node functions should fail on mobile keys
        XCTAssertThrowsError(try mobileKeys.nodeGetPublicKey()) { error in
            XCTAssertTrue(error is FFIError, "Node functions should fail on mobile keys")
        }
    }

    func testCoreErrorCodeUniqueness() throws {
        let errorCodes: Set<Int32> = [
            FFIError.nullArgument("").errorCode,
            FFIError.invalidHandle("").errorCode,
            FFIError.notInitialized.errorCode,
            FFIError.wrongManagerType("").errorCode,
            FFIError.operationFailed("").errorCode,
            FFIError.serializationFailed("").errorCode,
            FFIError.keystoreFailed("").errorCode,
            FFIError.memoryAllocation("").errorCode,
            FFIError.lockError("").errorCode,
            FFIError.invalidUTF8("").errorCode,
            FFIError.invalidArgument("").errorCode
        ]

        XCTAssertEqual(errorCodes.count, 11, "All error codes should be unique across platforms")

        // Verify specific error codes match Rust
        XCTAssertEqual(FFIError.nullArgument("").errorCode, 1, "Null argument error code should be 1")
        XCTAssertEqual(FFIError.invalidHandle("").errorCode, 2, "Invalid handle error code should be 2")
        XCTAssertEqual(FFIError.notInitialized.errorCode, 3, "Not initialized error code should be 3")
        XCTAssertEqual(FFIError.wrongManagerType("").errorCode, 4, "Wrong manager type error code should be 4")
        XCTAssertEqual(FFIError.operationFailed("").errorCode, 5, "Operation failed error code should be 5")
        XCTAssertEqual(FFIError.serializationFailed("").errorCode, 6, "Serialization failed error code should be 6")
        XCTAssertEqual(FFIError.keystoreFailed("").errorCode, 7, "Keystore failed error code should be 7")
        XCTAssertEqual(FFIError.memoryAllocation("").errorCode, 12, "Memory allocation error code should be 12")
        XCTAssertEqual(FFIError.lockError("").errorCode, 9, "Lock error error code should be 9")
        XCTAssertEqual(FFIError.invalidUTF8("").errorCode, 10, "Invalid UTF8 error code should be 10")
        XCTAssertEqual(FFIError.invalidArgument("").errorCode, 11, "Invalid argument error code should be 11")
    }

    // MARK: - Basic Encryption Tests

    func testCoreBasicEncryptionOperations() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let testData = Data("This is test data for encryption".utf8)

        // Test local data encryption
        let encryptedData = try keys.nodeEncryptLocalData(testData)
        XCTAssertFalse(encryptedData.isEmpty, "Encrypted data should not be empty")
        XCTAssertNotEqual(encryptedData, testData, "Encrypted data should be different from original")

        // Test decryption
        let decryptedData = try keys.nodeDecryptLocalData(encryptedData)
        XCTAssertEqual(decryptedData, testData, "Decrypted data should match original")

        // Test envelope encryption
        let envelopeEncrypted = try keys.nodeEncryptWithEnvelope(
            data: testData,
            networkPublicKey: nil,
            profileKeys: []
        )
        XCTAssertFalse(envelopeEncrypted.isEmpty, "Envelope encrypted data should not be empty")
        XCTAssertNotEqual(envelopeEncrypted, testData, "Envelope encrypted data should be different from original")
    }

    func testCoreBasicDecryptionOperations() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let testData = Data("This is test data for decryption".utf8)

        // Test local data encryption/decryption cycle
        let encryptedData = try keys.nodeEncryptLocalData(testData)
        let decryptedData = try keys.nodeDecryptLocalData(encryptedData)
        XCTAssertEqual(decryptedData, testData, "Decrypted data should match original")

        // Test envelope encryption/decryption cycle
        let envelopeEncrypted = try keys.nodeEncryptWithEnvelope(
            data: testData,
            networkPublicKey: nil,
            profileKeys: []
        )
        // Note: Envelope decryption requires the same keys that encrypted it
        // This test verifies encryption works, decryption would need proper setup
        XCTAssertFalse(envelopeEncrypted.isEmpty, "Envelope encrypted data should not be empty")

        // Test with different data sizes
        let smallData = Data("Hi".utf8)
        let largeData = Data(String(repeating: "A", count: 1000).utf8)

        let smallEncrypted = try keys.nodeEncryptLocalData(smallData)
        let smallDecrypted = try keys.nodeDecryptLocalData(smallEncrypted)
        XCTAssertEqual(smallDecrypted, smallData, "Small data should encrypt/decrypt correctly")

        let largeEncrypted = try keys.nodeEncryptLocalData(largeData)
        let largeDecrypted = try keys.nodeDecryptLocalData(largeEncrypted)
        XCTAssertEqual(largeDecrypted, largeData, "Large data should encrypt/decrypt correctly")
    }

    // MARK: - Parameter Validation Tests

    func testCoreParameterValidation() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        // Test with empty data
        let emptyData = Data()
        XCTAssertNoThrow(try keys.nodeEncryptLocalData(emptyData), "Should handle empty data")

        // Test with nil network public key
        let testData = Data("Test data".utf8)
        XCTAssertNoThrow(try keys.nodeEncryptWithEnvelope(
            data: testData,
            networkPublicKey: nil,
            profileKeys: []
        ), "Should handle nil network public key")

        // Test with empty profile keys array
        XCTAssertNoThrow(try keys.nodeEncryptWithEnvelope(
            data: testData,
            networkPublicKey: nil,
            profileKeys: []
        ), "Should handle empty profile keys array")

        // Test with valid network public key
        let networkKey = try keys.nodeGetPublicKey()
        XCTAssertNoThrow(try keys.nodeEncryptWithEnvelope(
            data: testData,
            networkPublicKey: networkKey,
            profileKeys: []
        ), "Should handle valid network public key")
    }

    func testCoreHandleValidation() throws {
        // Test that operations fail on uninitialized handles
        let keys = KeysFFI()

        XCTAssertThrowsError(try keys.nodeGetPublicKey()) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError for uninitialized handle")
        }

        XCTAssertThrowsError(try keys.mobileInitializeUserRootKey()) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError for uninitialized handle")
        }

        // Test that operations work after proper initialization
        try keys.initializeAsNode()
        XCTAssertNoThrow(try keys.nodeGetPublicKey(), "Should work after proper initialization")

        let mobileKeys = KeysFFI()
        try mobileKeys.initializeAsMobile()
        XCTAssertNoThrow(try mobileKeys.mobileInitializeUserRootKey(), "Should work after proper initialization")
    }
}
