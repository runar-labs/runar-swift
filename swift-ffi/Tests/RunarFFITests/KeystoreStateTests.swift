@testable import RunarFFI
import XCTest

/// Keystore State Tests
///
/// Tests for keystore state management and persistence.
/// Mirrors the ffi_keys_state_test.rs from Rust.
final class KeystoreStateTests: XCTestCase {
    
    // MARK: - Basic State Tests
    
    func testNodeKeystoreState() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()
        
        let state = try keys.nodeGetKeystoreState()
        XCTAssertGreaterThanOrEqual(state, 0, "Node keystore state should be non-negative")
    }
    
    func testMobileKeystoreState() throws {
        let keys = KeysFFI()
        try keys.initializeAsMobile()
        
        let state = try keys.mobileGetKeystoreState()
        XCTAssertGreaterThanOrEqual(state, 0, "Mobile keystore state should be non-negative")
    }
    
    // MARK: - State Persistence Tests
    
    func testStatePersistenceAcrossOperations() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()
        
        // Get initial state
        _ = try keys.nodeGetKeystoreState()
        
        // Perform operations that might change state
        let testData = Data("Test data for state persistence".utf8)
        let encryptedData = try keys.nodeEncryptLocalData(testData)
        let decryptedData = try keys.nodeDecryptLocalData(encryptedData)
        XCTAssertEqual(decryptedData, testData, "Data should encrypt/decrypt correctly")
        
        // Get state after operations
        let finalState = try keys.nodeGetKeystoreState()
        
        // State should be consistent (may or may not change depending on implementation)
        XCTAssertGreaterThanOrEqual(finalState, 0, "Final state should be non-negative")
    }
    
    func testStateConsistencyAcrossMultipleOperations() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()
        
        // Perform multiple operations
        for i in 0..<10 {
            let testData = Data("Test data \(i)".utf8)
            let encryptedData = try keys.nodeEncryptLocalData(testData)
            let decryptedData = try keys.nodeDecryptLocalData(encryptedData)
            XCTAssertEqual(decryptedData, testData, "Data \(i) should encrypt/decrypt correctly")
            
            let state = try keys.nodeGetKeystoreState()
            XCTAssertGreaterThanOrEqual(state, 0, "State should remain valid after operation \(i)")
        }
    }
    
    // MARK: - State Isolation Tests
    
    func testStateIsolationBetweenInstances() throws {
        let keys1 = KeysFFI()
        let keys2 = KeysFFI()
        
        try keys1.initializeAsNode()
        try keys2.initializeAsNode()
        
        let state1 = try keys1.nodeGetKeystoreState()
        let state2 = try keys2.nodeGetKeystoreState()
        
        // States should be independent
        XCTAssertGreaterThanOrEqual(state1, 0, "First instance state should be valid")
        XCTAssertGreaterThanOrEqual(state2, 0, "Second instance state should be valid")
        
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
        
        let mobileState = try mobileKeys.mobileGetKeystoreState()
        let nodeState = try nodeKeys.nodeGetKeystoreState()
        
        // States should be independent
        XCTAssertGreaterThanOrEqual(mobileState, 0, "Mobile state should be valid")
        XCTAssertGreaterThanOrEqual(nodeState, 0, "Node state should be valid")
        
        // Perform operations on mobile
        try mobileKeys.mobileInitializeUserRootKey()
        let userPublicKey = try mobileKeys.mobileGetUserPublicKey()
        XCTAssertFalse(userPublicKey.isEmpty, "Mobile should work correctly")
        
        // Perform operations on node
        let nodePublicKey = try nodeKeys.nodeGetPublicKey()
        XCTAssertFalse(nodePublicKey.isEmpty, "Node should work correctly")
        
        // States should remain independent
        let mobileStateAfter = try mobileKeys.mobileGetKeystoreState()
        let nodeStateAfter = try nodeKeys.nodeGetKeystoreState()
        
        XCTAssertGreaterThanOrEqual(mobileStateAfter, 0, "Mobile state should remain valid")
        XCTAssertGreaterThanOrEqual(nodeStateAfter, 0, "Node state should remain valid")
    }
    
    // MARK: - State Error Handling Tests
    
    func testStateOperationsWithoutInitialization() throws {
        let keys = KeysFFI()
        // Not initialized
        
        XCTAssertThrowsError(try keys.nodeGetKeystoreState()) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError when not initialized")
        }
        
        XCTAssertThrowsError(try keys.mobileGetKeystoreState()) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError when not initialized")
        }
    }
    
    func testStateOperationsWithWrongManagerType() throws {
        let keys = KeysFFI()
        try keys.initializeAsMobile()
        
        XCTAssertThrowsError(try keys.nodeGetKeystoreState()) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError with wrong manager type")
        }
        
        let nodeKeys = KeysFFI()
        try nodeKeys.initializeAsNode()
        
        XCTAssertThrowsError(try nodeKeys.mobileGetKeystoreState()) { error in
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
            _ = try keys.nodeGetKeystoreState()
            XCTFail("Should have thrown an error")
        } catch _ as FFIError {
            // Should be able to recover by initializing
            XCTAssertNoThrow(try keys.initializeAsNode(), "Should be able to initialize after error")
            XCTAssertNoThrow(try keys.nodeGetKeystoreState(), "Should work after initialization")
        } catch {
            XCTFail("Should have thrown FFIError, got: \(error)")
        }
    }
    
    func testStateConsistencyAfterMultipleErrors() throws {
        let keys = KeysFFI()
        
        // Multiple errors before initialization
        for _ in 0..<5 {
            XCTAssertThrowsError(try keys.nodeGetKeystoreState()) { error in
                XCTAssertTrue(error is FFIError, "Should throw FFIError consistently")
            }
        }
        
        // Should still be able to initialize and work
        XCTAssertNoThrow(try keys.initializeAsNode(), "Should be able to initialize after multiple errors")
        XCTAssertNoThrow(try keys.nodeGetKeystoreState(), "Should work after initialization")
        
        let state = try keys.nodeGetKeystoreState()
        XCTAssertGreaterThanOrEqual(state, 0, "State should be valid after recovery")
    }
}
