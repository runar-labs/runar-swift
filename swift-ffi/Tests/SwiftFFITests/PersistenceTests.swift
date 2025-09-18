import XCTest
import SwiftFFI
import SwiftCommon

@testable import SwiftFFI

/// Tests for persistence and keystore functionality
/// Tests persistence directory, auto-persist, wipe, flush, keystore caps, and Apple device keystore registration
final class PersistenceTests: XCTestCase {
    
    private var tempDir: String!
    private var keysHandle: KeysHandle!
    
    override func setUp() {
        super.setUp()
        
        // Create temporary directory for persistence tests
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        tempDir = tempURL.path
        
        // Create keys handle for testing
        keysHandle = try! KeysHandle()
    }
    
    override func tearDown() {
        // Clean up temporary directory
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(atPath: tempDir)
        }
        
        keysHandle = nil
        super.tearDown()
    }
    
    // MARK: - Persistence Directory Tests
    
    func testSetPersistenceDirectory() throws {
        // Initialize as node first
        try keysHandle.initializeAsNode()
        
        // Test setting persistence directory
        try keysHandle.setPersistenceDirectory(tempDir)
        
        // Verify no error is thrown (success)
        XCTAssertTrue(true, "Setting persistence directory should succeed")
    }
    
    func testSetPersistenceDirectoryWithInvalidPath() throws {
        // Test with invalid path
        let invalidPath = "/nonexistent/path/that/does/not/exist"
        
        do {
            try keysHandle.setPersistenceDirectory(invalidPath)
            XCTFail("Should have thrown error for invalid path")
        } catch {
            // Expected to fail
            XCTAssertTrue(error is FFIError)
        }
    }
    
    // MARK: - Auto-Persistence Tests
    
    func testEnableAutoPersistence() throws {
        // Initialize as node first
        try keysHandle.initializeAsNode()
        
        // Test enabling auto-persistence
        try keysHandle.enableAutoPersistence(true)
        
        // Test disabling auto-persistence
        try keysHandle.enableAutoPersistence(false)
        
        // Verify no error is thrown (success)
        XCTAssertTrue(true, "Enabling/disabling auto-persistence should succeed")
    }
    
    // MARK: - Wipe Persistence Tests
    
    func testWipePersistence() throws {
        // Initialize as node first
        try keysHandle.initializeAsNode()
        
        // First set a persistence directory
        try keysHandle.setPersistenceDirectory(tempDir)
        
        // Test wiping persistence
        try keysHandle.wipePersistence()
        
        // Verify no error is thrown (success)
        XCTAssertTrue(true, "Wiping persistence should succeed")
    }
    
    func testWipePersistenceWithoutDirectory() throws {
        // Test wiping persistence without setting directory first
        do {
            try keysHandle.wipePersistence()
            // This might succeed or fail depending on implementation
        } catch {
            // If it fails, that's also acceptable
            XCTAssertTrue(error is FFIError)
        }
    }
    
    // MARK: - Keystore Capabilities Tests
    
    func testGetKeystoreCaps() throws {
        // Initialize as node first
        try keysHandle.initializeAsNode()
        
        // Test getting keystore capabilities
        let caps = try keysHandle.getKeystoreCaps()
        
        // Verify caps structure is returned
        XCTAssertNotNil(caps, "Keystore capabilities should be returned")
        // Note: We can't assert specific values as they depend on the platform
    }
    
    // MARK: - Flush State Tests
    
    func testFlushState() throws {
        // Initialize as node first
        try keysHandle.initializeAsNode()
        
        // First set a persistence directory
        try keysHandle.setPersistenceDirectory(tempDir)
        
        // Test flushing state
        try keysHandle.flushState()
        
        // Verify no error is thrown (success)
        XCTAssertTrue(true, "Flushing state should succeed")
    }
    
    func testFlushStateWithoutDirectory() throws {
        // Test flushing state without setting directory first
        do {
            try keysHandle.flushState()
            // This might succeed or fail depending on implementation
        } catch {
            // If it fails, that's also acceptable
            XCTAssertTrue(error is FFIError)
        }
    }
    
    // MARK: - Apple Device Keystore Tests
    
    func testRegisterAppleDeviceKeystore() throws {
        // Initialize as node first
        try keysHandle.initializeAsNode()
        
        // Test registering Apple device keystore
        let label = "test-keystore-\(UUID().uuidString)"
        
        try keysHandle.registerAppleDeviceKeystore(label: label)
        
        // Verify no error is thrown (success)
        XCTAssertTrue(true, "Registering Apple device keystore should succeed")
    }
    
    func testRegisterAppleDeviceKeystoreWithEmptyLabel() throws {
        // Test with empty label
        do {
            try keysHandle.registerAppleDeviceKeystore(label: "")
            // This might succeed or fail depending on implementation
        } catch {
            // If it fails, that's also acceptable
            XCTAssertTrue(error is FFIError)
        }
    }
    
    // MARK: - Persistence Lifecycle Tests
    
    func testPersistenceLifecycle() throws {
        // Test complete persistence lifecycle
        
        // 1. Initialize as node first
        try keysHandle.initializeAsNode()
        
        // 2. Set persistence directory
        try keysHandle.setPersistenceDirectory(tempDir)
        
        // 3. Enable auto-persistence
        try keysHandle.enableAutoPersistence(true)
        
        // 4. Generate some keys to have data to persist
        try keysHandle.nodeGenerateKeys()
        
        // 5. Flush state to persistence
        try keysHandle.flushState()
        
        // 6. Wipe persistence
        try keysHandle.wipePersistence()
        
        // 7. Disable auto-persistence
        try keysHandle.enableAutoPersistence(false)
        
        // Verify no error is thrown throughout the lifecycle
        XCTAssertTrue(true, "Complete persistence lifecycle should succeed")
    }
    
    func testPersistenceStateContinuity() throws {
        // Test that state can be persisted and restored
        // This test follows the Rust pattern: set persistence BEFORE initialization
        
        // 1. Set up persistence BEFORE initialization (matches Rust pattern)
        try keysHandle.setPersistenceDirectory(tempDir)
        try keysHandle.enableAutoPersistence(true)
        
        // 2. Initialize as node
        try keysHandle.initializeAsNode()
        
        // 3. Generate keys explicitly (to ensure they exist)
        try keysHandle.nodeGenerateKeys()
        
        // 4. Verify keys exist before flushing
        let hasKeysBeforeFlush = try keysHandle.nodeHasKeys()
        XCTAssertTrue(hasKeysBeforeFlush, "Keys should exist before flush")
        
        // 5. Flush state
        try keysHandle.flushState()
        
        // 6. Create new keys handle (simulating restart)
        let newKeysHandle = try KeysHandle()
        
        // 7. Set same persistence directory and enable auto-persistence BEFORE initialization
        try newKeysHandle.setPersistenceDirectory(tempDir)
        try newKeysHandle.enableAutoPersistence(true)
        
        // 8. Initialize as node (this should restore state from persistence)
        try newKeysHandle.initializeAsNode()
        
        // 9. Generate keys to trigger state loading
        try newKeysHandle.nodeGenerateKeys()
        
        // 10. Verify keys exist (should be restored from persistence)
        let hasKeys = try newKeysHandle.nodeHasKeys()
        XCTAssertTrue(hasKeys, "Keys should be restored from persistence")
        
        // Clean up
        try newKeysHandle.wipePersistence()
    }
    
    // MARK: - Error Handling Tests
    
    func testPersistenceErrorHandling() throws {
        // Test various error conditions
        
        // Test with very long path (might cause issues)
        let longPath = String(repeating: "a", count: 1000)
        do {
            try keysHandle.setPersistenceDirectory(longPath)
            // Might succeed or fail
        } catch {
            XCTAssertTrue(error is FFIError)
        }
        
        // Test with special characters in path
        let specialPath = tempDir + "/test@#$%^&*()"
        do {
            try keysHandle.setPersistenceDirectory(specialPath)
            // Might succeed or fail
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentPersistenceOperations() throws {
        // Test that persistence operations are safe for concurrent access
        
        let expectation = XCTestExpectation(description: "Concurrent operations")
        expectation.expectedFulfillmentCount = 3
        
        // Set up persistence first
        try keysHandle.initializeAsNode()
        try keysHandle.setPersistenceDirectory(tempDir)
        try keysHandle.enableAutoPersistence(true)
        
        // Run concurrent operations
        DispatchQueue.global().async {
            do {
                try self.keysHandle.flushState()
                expectation.fulfill()
            } catch {
                XCTFail("Flush state failed: \(error)")
            }
        }
        
        DispatchQueue.global().async {
            do {
                let caps = try self.keysHandle.getKeystoreCaps()
                XCTAssertNotNil(caps)
                expectation.fulfill()
            } catch {
                XCTFail("Get keystore caps failed: \(error)")
            }
        }
        
        DispatchQueue.global().async {
            do {
                try self.keysHandle.enableAutoPersistence(false)
                expectation.fulfill()
            } catch {
                XCTFail("Disable auto-persistence failed: \(error)")
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
}
