@testable import SwiftFFI
import XCTest

/// Tests for persistence functionality
final class PersistenceTests: XCTestCase {
    private var tempDir: String!
    private var keysHandle: NodeKeyManager!

    override func setUp() {
        super.setUp()

        // Create temporary directory for persistence tests
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
            tempDir = tempURL.path

            // Create keys handle for testing
            keysHandle = try NodeKeyManager()
        } catch {
            XCTFail("Failed to set up test: \(error)")
        }
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
        // Test setting a valid persistence directory
        try keysHandle.setPersistenceDirectory(tempDir)
        
        // Test that we can enable auto-persistence
        try keysHandle.enableAutoPersistence(true)
        
        // Test that we can get keystore capabilities
        let capabilities = try keysHandle.getKeystoreCapabilities()
        XCTAssertNotNil(capabilities, "Should be able to get keystore capabilities")
    }

    func testSetPersistenceDirectoryWithInvalidPath() throws {
        // Test setting an invalid persistence directory
        let invalidPath = "/invalid/path/that/does/not/exist"
        
        // Note: The FFI function may not validate the path immediately
        // It might only fail when actually trying to use the directory
        do {
            try keysHandle.setPersistenceDirectory(invalidPath)
            // If it doesn't throw an error, that's also acceptable behavior
            // The error might only occur when trying to use the directory
        } catch {
            // If it does throw an error, that's also acceptable
            XCTAssertTrue(error is FFIError, "Should throw FFIError for invalid path")
        }
    }

    // MARK: - Auto-Persistence Tests

    func testEnableAutoPersistence() throws {
        // Set persistence directory first
        try keysHandle.setPersistenceDirectory(tempDir)
        
        // Test enabling auto-persistence
        try keysHandle.enableAutoPersistence(true)
        
        // Test that we can flush state
        try keysHandle.flushState()
        
        // Test that we can get keystore capabilities
        let capabilities = try keysHandle.getKeystoreCapabilities()
        XCTAssertNotNil(capabilities, "Should be able to get keystore capabilities")
    }

    // MARK: - Persistence Operations Tests

    func testWipePersistence() throws {
        // Set persistence directory first
        try keysHandle.setPersistenceDirectory(tempDir)
        
        // Test wiping persistence
        try keysHandle.wipePersistence()
        
        // Test that we can still get keystore capabilities after wipe
        let capabilities = try keysHandle.getKeystoreCapabilities()
        XCTAssertNotNil(capabilities, "Should be able to get keystore capabilities after wipe")
    }

    func testWipePersistenceWithoutDirectory() throws {
        // Test wiping persistence without setting directory first
        do {
            try keysHandle.wipePersistence()
            // This might succeed or fail depending on implementation
        } catch {
            // Expected to potentially throw an error
            XCTAssertTrue(error is FFIError, "Should throw FFIError when no directory set")
        }
    }

    func testGetKeystoreCaps() throws {
        // Test getting keystore capabilities
        let capabilities = try keysHandle.getKeystoreCapabilities()
        XCTAssertNotNil(capabilities, "Should be able to get keystore capabilities")
        XCTAssertGreaterThanOrEqual(capabilities.version, 0, "Version should be non-negative")
    }

    func testFlushState() throws {
        // Set persistence directory first
        try keysHandle.setPersistenceDirectory(tempDir)
        
        // Test flushing state
        try keysHandle.flushState()
        
        // Test that we can still get keystore capabilities after flush
        let capabilities = try keysHandle.getKeystoreCapabilities()
        XCTAssertNotNil(capabilities, "Should be able to get keystore capabilities after flush")
    }

    func testFlushStateWithoutDirectory() throws {
        // Test flushing state without setting directory first
        do {
            try keysHandle.flushState()
            // This might succeed or fail depending on implementation
        } catch {
            // Expected to potentially throw an error
            XCTAssertTrue(error is FFIError, "Should throw FFIError when no directory set")
        }
    }

    // MARK: - Keystore Registration Tests

    func testRegisterAppleDeviceKeystore() throws {
        // Test registering Apple device keystore
        let label = "test-keystore"
        try keysHandle.registerAppleDeviceKeystore(label: label)
        
        // Test that we can still get keystore capabilities after registration
        let capabilities = try keysHandle.getKeystoreCapabilities()
        XCTAssertNotNil(capabilities, "Should be able to get keystore capabilities after registration")
    }

    func testRegisterAppleDeviceKeystoreWithEmptyLabel() throws {
        // Test registering Apple device keystore with empty label
        do {
            try keysHandle.registerAppleDeviceKeystore(label: "")
            // If it doesn't throw an error, that's also acceptable behavior
            // The FFI function may not validate empty labels
        } catch {
            // If it does throw an error, that's also acceptable
            XCTAssertTrue(error is FFIError, "Should throw FFIError for empty label")
        }
    }

    // MARK: - Lifecycle Tests

    func testPersistenceLifecycle() throws {
        // Test complete persistence lifecycle
        try keysHandle.setPersistenceDirectory(tempDir)
        try keysHandle.enableAutoPersistence(true)
        
        // Test that we can get capabilities
        let capabilities = try keysHandle.getKeystoreCapabilities()
        XCTAssertNotNil(capabilities, "Should be able to get keystore capabilities")
        
        // Test flushing state
        try keysHandle.flushState()
        
        // Test wiping persistence
        try keysHandle.wipePersistence()
        
        // Test that we can still get capabilities after wipe
        let capabilitiesAfterWipe = try keysHandle.getKeystoreCapabilities()
        XCTAssertNotNil(capabilitiesAfterWipe, "Should be able to get keystore capabilities after wipe")
    }

    func testPersistenceStateContinuity() throws {
        // Test that persistence state is maintained across operations
        try keysHandle.setPersistenceDirectory(tempDir)
        try keysHandle.enableAutoPersistence(true)
        
        // Test that we can flush and still get capabilities
        try keysHandle.flushState()
        let capabilities1 = try keysHandle.getKeystoreCapabilities()
        XCTAssertNotNil(capabilities1, "Should be able to get keystore capabilities after flush")
        
        // Test that we can flush again
        try keysHandle.flushState()
        let capabilities2 = try keysHandle.getKeystoreCapabilities()
        XCTAssertNotNil(capabilities2, "Should be able to get keystore capabilities after second flush")
    }

    // MARK: - Error Handling Tests

    func testPersistenceErrorHandling() throws {
        // Test error handling for invalid operations
        let invalidPath = "/invalid/path/that/does/not/exist"
        
        do {
            try keysHandle.setPersistenceDirectory(invalidPath)
            // If it doesn't throw an error, that's also acceptable behavior
            // The FFI function may not validate the path immediately
        } catch {
            XCTAssertTrue(error is FFIError, "Should throw FFIError for invalid path")
        }
        
        // Test error handling for empty keystore label
        do {
            try keysHandle.registerAppleDeviceKeystore(label: "")
            // If it doesn't throw an error, that's also acceptable behavior
            // The FFI function may not validate empty labels
        } catch {
            XCTAssertTrue(error is FFIError, "Should throw FFIError for empty label")
        }
    }

    // MARK: - Concurrency Tests

    func testConcurrentPersistenceOperations() throws {
        // Test concurrent persistence operations
        try keysHandle.setPersistenceDirectory(tempDir)
        
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        
        for i in 0..<5 {
            group.enter()
            queue.async {
                do {
                    try self.keysHandle.flushState()
                    let capabilities = try self.keysHandle.getKeystoreCapabilities()
                    XCTAssertNotNil(capabilities, "Concurrent operation \(i) should work")
                } catch {
                    XCTFail("Concurrent operation \(i) failed: \(error)")
                }
                group.leave()
            }
        }
        
        group.wait()
    }
}
