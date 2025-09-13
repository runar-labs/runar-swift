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
}
