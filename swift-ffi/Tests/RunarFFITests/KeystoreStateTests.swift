@testable import RunarFFI
import XCTest

/// Keystore State Tests
///
/// Tests for keystore state management and persistence.
/// Note: getKeystoreState functions do not exist in Rust FFI, so these tests focus on actual functionality.
final class KeystoreStateTests: XCTestCase {
    // MARK: - Basic Functionality Tests

    func testNodeInitialization() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        // Test that node is properly initialized by checking if we can get the public key
        let publicKey = try keys.nodeGetPublicKey()
        XCTAssertFalse(publicKey.isEmpty, "Node should be properly initialized")
    }

    func testMobileInitialization() throws {
        let keys = KeysFFI()
        try keys.initializeAsMobile()

        // Test that mobile is properly initialized by checking if we can get the user public key
        try keys.mobileInitializeUserRootKey()
        let userPublicKey = try keys.mobileGetUserPublicKey()
        XCTAssertFalse(userPublicKey.isEmpty, "Mobile should be properly initialized")
    }

    // MARK: - State Persistence Tests

    func testStatePersistenceAcrossOperations() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        // Perform operations that might change state
        let testData = Data("Test data for state persistence".utf8)
        let encryptedData = try keys.nodeEncryptLocalData(testData)
        let decryptedData = try keys.nodeDecryptLocalData(encryptedData)
        XCTAssertEqual(decryptedData, testData, "Data should encrypt/decrypt correctly")
    }

    func testStateConsistencyAcrossMultipleOperations() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        // Perform multiple operations
        for i in 0 ..< 10 {
            let testData = Data("Test data \(i)".utf8)
            let encryptedData = try keys.nodeEncryptLocalData(testData)
            let decryptedData = try keys.nodeDecryptLocalData(encryptedData)
            XCTAssertEqual(decryptedData, testData, "Data \(i) should encrypt/decrypt correctly")
        }
    }

    // MARK: - State Isolation Tests

    func testStateIsolationBetweenInstances() throws {
        let keys1 = KeysFFI()
        let keys2 = KeysFFI()

        try keys1.initializeAsNode()
        try keys2.initializeAsNode()

        // Test that both instances work independently
        let publicKey1 = try keys1.nodeGetPublicKey()
        let publicKey2 = try keys2.nodeGetPublicKey()

        XCTAssertFalse(publicKey1.isEmpty, "First instance should work correctly")
        XCTAssertFalse(publicKey2.isEmpty, "Second instance should work correctly")

        // Perform operations on first instance
        let testData = Data("Test data for isolation".utf8)
        let encryptedData = try keys1.nodeEncryptLocalData(testData)
        let decryptedData = try keys1.nodeDecryptLocalData(encryptedData)
        XCTAssertEqual(decryptedData, testData, "First instance should work correctly")

        // Second instance should still work independently
        let encryptedData2 = try keys2.nodeEncryptLocalData(testData)
        let decryptedData2 = try keys2.nodeDecryptLocalData(encryptedData2)
        XCTAssertEqual(decryptedData2, testData, "Second instance should work independently")
    }

    func testStateIsolationBetweenMobileAndNode() throws {
        let mobileKeys = KeysFFI()
        let nodeKeys = KeysFFI()

        try mobileKeys.initializeAsMobile()
        try nodeKeys.initializeAsNode()

        // Test that both types work independently
        try mobileKeys.mobileInitializeUserRootKey()
        let userPublicKey = try mobileKeys.mobileGetUserPublicKey()
        XCTAssertFalse(userPublicKey.isEmpty, "Mobile should work correctly")

        let nodePublicKey = try nodeKeys.nodeGetPublicKey()
        XCTAssertFalse(nodePublicKey.isEmpty, "Node should work correctly")
    }

    // MARK: - State Error Handling Tests

    func testOperationsWithoutInitialization() throws {
        let keys = KeysFFI()
        // Not initialized

        XCTAssertThrowsError(try keys.nodeGetPublicKey()) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError when not initialized")
        }

        XCTAssertThrowsError(try keys.mobileGetUserPublicKey()) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError when not initialized")
        }
    }

    func testOperationsWithWrongManagerType() throws {
        let keys = KeysFFI()
        try keys.initializeAsMobile()

        XCTAssertThrowsError(try keys.nodeGetPublicKey()) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError with wrong manager type")
        }

        let nodeKeys = KeysFFI()
        try nodeKeys.initializeAsNode()

        XCTAssertThrowsError(try nodeKeys.mobileGetUserPublicKey()) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError with wrong manager type")
        }
    }

    // MARK: - State Persistence Directory Tests

    func testSetPersistenceDir() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        let tempDir = NSTemporaryDirectory()
        XCTAssertNoThrow(try keys.setPersistenceDirectory(URL(fileURLWithPath: tempDir)), "Should set persistence directory")
    }

    func testEnableAutoPersist() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        XCTAssertNoThrow(try keys.enableAutoPersist(true), "Should enable auto-persistence")
    }

    func testWipePersistence() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        XCTAssertNoThrow(try keys.wipePersistence(), "Should wipe persistence")
    }

    func testFlushState() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()

        XCTAssertNoThrow(try keys.flushState(), "Should flush state")
    }

    // MARK: - State Recovery Tests

    func testStateRecoveryAfterError() throws {
        let keys = KeysFFI()

        // Test error handling before initialization
        do {
            _ = try keys.nodeGetPublicKey()
            XCTFail("Should have thrown an error")
        } catch _ as FFIError {
            // Should be able to recover by initializing
            XCTAssertNoThrow(try keys.initializeAsNode(), "Should be able to initialize after error")
            XCTAssertNoThrow(try keys.nodeGetPublicKey(), "Should work after initialization")
        } catch {
            XCTFail("Should have thrown FFIError, got: \(error)")
        }
    }

    func testStateConsistencyAfterMultipleErrors() throws {
        let keys = KeysFFI()

        // Multiple errors before initialization
        for _ in 0 ..< 5 {
            XCTAssertThrowsError(try keys.nodeGetPublicKey()) { error in
                XCTAssertTrue(error is FFIError, "Should throw FFIError consistently")
            }
        }

        // Should still be able to initialize and work
        XCTAssertNoThrow(try keys.initializeAsNode(), "Should be able to initialize after multiple errors")
        XCTAssertNoThrow(try keys.nodeGetPublicKey(), "Should work after initialization")

        let publicKey = try keys.nodeGetPublicKey()
        XCTAssertFalse(publicKey.isEmpty, "Should be valid after recovery")
    }
}
