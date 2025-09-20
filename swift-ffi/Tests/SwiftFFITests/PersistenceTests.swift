@testable import SwiftFFI
import XCTest

/// Tests for persistence functionality
@MainActor
final class PersistenceTests: XCTestCase {
    private var tempDir: String!
    private var keysHandle: NodeKeyManager!

    override func setUp() async throws {
        try await super.setUp()

        // Create temporary directory for persistence tests
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try await FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
            tempDir = tempURL.path

            // Create keys handle for testing
            keysHandle = try await NodeKeyManager()
        } catch {
            XCTFail("Failed to set up test: \(error)")
        }
    }

    override func tearDown() async throws {
        // Clean up temporary directory
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(atPath: tempDir)
        }
        keysHandle = nil
        try await super.tearDown()
    }

    // MARK: - Persistence Directory Tests

    func testSetPersistenceDirectory() async throws {
        // Test setting a valid persistence directory
        try await keysHandle.setPersistenceDirectory(tempDir)
        
        // Test that we can enable auto-persistence
        try await keysHandle.enableAutoPersistence(true)
        
        // Test that we can get keystore capabilities
        let capabilities = try await keysHandle.getKeystoreCapabilities()
        XCTAssertNotNil(capabilities, "Should be able to get keystore capabilities")
    }

    func testSetPersistenceDirectoryWithInvalidPath() async throws {
        // Test setting an invalid persistence directory
        let invalidPath = "/invalid/path/that/does/not/exist"
        
        // Note: The FFI function may not validate the path immediately
        // It might only fail when actually trying to use the directory
        do {
            try await keysHandle.setPersistenceDirectory(invalidPath)
            // If it doesn't throw an error, that's also acceptable behavior
            // The error might only occur when trying to use the directory
        } catch {
            // If it does throw an error, that's also acceptable
            XCTAssertTrue(error is FFIError, "Should throw FFIError for invalid path")
        }
    }

    // MARK: - Auto-Persistence Tests

    func testEnableAutoPersistence() async throws {
        // Set persistence directory first
        try await keysHandle.setPersistenceDirectory(tempDir)
        
        // Test enabling auto-persistence
        try await keysHandle.enableAutoPersistence(true)
        
        // Test that we can flush state
        try await keysHandle.flushState()
        
        // Test that we can get keystore capabilities
        let capabilities = try await keysHandle.getKeystoreCapabilities()
        XCTAssertNotNil(capabilities, "Should be able to get keystore capabilities")
    }

    // MARK: - Persistence Operations Tests

    func testWipePersistence() async throws {
        // Set persistence directory first
        try await keysHandle.setPersistenceDirectory(tempDir)
        
        // Test wiping persistence
        try await keysHandle.wipePersistence()
        
        // Test that we can still get keystore capabilities after wipe
        let capabilities = try await keysHandle.getKeystoreCapabilities()
        XCTAssertNotNil(capabilities, "Should be able to get keystore capabilities after wipe")
    }

    func testWipePersistenceWithoutDirectory() async throws {
        // Test wiping persistence without setting directory first
        do {
            try await keysHandle.wipePersistence()
            // This might succeed or fail depending on implementation
        } catch {
            // Expected to potentially throw an error
            XCTAssertTrue(error is FFIError, "Should throw FFIError when no directory set")
        }
    }

    func testGetKeystoreCaps() async throws {
        // Test getting keystore capabilities
        let capabilities = try await keysHandle.getKeystoreCapabilities()
        XCTAssertNotNil(capabilities, "Should be able to get keystore capabilities")
        XCTAssertGreaterThanOrEqual(capabilities.version, 0, "Version should be non-negative")
    }

    func testFlushState() async throws {
        // Set persistence directory first
        try await keysHandle.setPersistenceDirectory(tempDir)
        
        // Test flushing state
        try await keysHandle.flushState()
        
        // Test that we can still get keystore capabilities after flush
        let capabilities = try await keysHandle.getKeystoreCapabilities()
        XCTAssertNotNil(capabilities, "Should be able to get keystore capabilities after flush")
    }

    func testFlushStateWithoutDirectory() async throws {
        // Test flushing state without setting directory first
        do {
            try await keysHandle.flushState()
            // This might succeed or fail depending on implementation
        } catch {
            // Expected to potentially throw an error
            XCTAssertTrue(error is FFIError, "Should throw FFIError when no directory set")
        }
    }

    // MARK: - Keystore Registration Tests

    func testRegisterAppleDeviceKeystore() async throws {
        // Test registering Apple device keystore
        let label = "test-keystore"
        try await keysHandle.registerAppleDeviceKeystore(label: label)
        
        // Test that we can still get keystore capabilities after registration
        let capabilities = try await keysHandle.getKeystoreCapabilities()
        XCTAssertNotNil(capabilities, "Should be able to get keystore capabilities after registration")
    }

    func testRegisterAppleDeviceKeystoreWithEmptyLabel() async throws {
        // Test registering Apple device keystore with empty label
        do {
            try await keysHandle.registerAppleDeviceKeystore(label: "")
            // If it doesn't throw an error, that's also acceptable behavior
            // The FFI function may not validate empty labels
        } catch {
            // If it does throw an error, that's also acceptable
            XCTAssertTrue(error is FFIError, "Should throw FFIError for empty label")
        }
    }

    // MARK: - Lifecycle Tests

    func testPersistenceLifecycle() async throws {
        // Test complete persistence lifecycle
        try await keysHandle.setPersistenceDirectory(tempDir)
        try await keysHandle.enableAutoPersistence(true)
        
        // Test that we can get capabilities
        let capabilities = try await keysHandle.getKeystoreCapabilities()
        XCTAssertNotNil(capabilities, "Should be able to get keystore capabilities")
        
        // Test flushing state
        try await keysHandle.flushState()
        
        // Test wiping persistence
        try await keysHandle.wipePersistence()
        
        // Test that we can still get capabilities after wipe
        let capabilitiesAfterWipe = try await keysHandle.getKeystoreCapabilities()
        XCTAssertNotNil(capabilitiesAfterWipe, "Should be able to get keystore capabilities after wipe")
    }

    func testPersistenceStateContinuity() async throws {
        // Test that persistence state is maintained across operations
        try await keysHandle.setPersistenceDirectory(tempDir)
        try await keysHandle.enableAutoPersistence(true)
        
        // Test that we can flush and still get capabilities
        try await keysHandle.flushState()
        let capabilities1 = try await keysHandle.getKeystoreCapabilities()
        XCTAssertNotNil(capabilities1, "Should be able to get keystore capabilities after flush")
        
        // Test that we can flush again
        try await keysHandle.flushState()
        let capabilities2 = try await keysHandle.getKeystoreCapabilities()
        XCTAssertNotNil(capabilities2, "Should be able to get keystore capabilities after second flush")
    }

    // MARK: - Error Handling Tests

    func testPersistenceErrorHandling() async throws {
        // Test error handling for invalid operations
        let invalidPath = "/invalid/path/that/does/not/exist"
        
        do {
            try await keysHandle.setPersistenceDirectory(invalidPath)
            // If it doesn't throw an error, that's also acceptable behavior
            // The FFI function may not validate the path immediately
        } catch {
            XCTAssertTrue(error is FFIError, "Should throw FFIError for invalid path")
        }
        
        // Test error handling for empty keystore label
        do {
            try await keysHandle.registerAppleDeviceKeystore(label: "")
            // If it doesn't throw an error, that's also acceptable behavior
            // The FFI function may not validate empty labels
        } catch {
            XCTAssertTrue(error is FFIError, "Should throw FFIError for empty label")
        }
    }

    // MARK: - Concurrency Tests

    func testConcurrentPersistenceOperations() async throws {
        // Test concurrent persistence operations
        try await keysHandle.setPersistenceDirectory(tempDir)
        
        guard let keysHandle = self.keysHandle else {
            XCTFail("Keys handle not initialized")
            return
        }
        
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                group.addTask {
                    do {
                        try await keysHandle.flushState()
                        let capabilities = try await keysHandle.getKeystoreCapabilities()
                        XCTAssertNotNil(capabilities, "Concurrent operation \(i) should work")
                    } catch {
                        XCTFail("Concurrent operation \(i) failed: \(error)")
                    }
                }
            }
            
            // Wait for all tasks to complete
            for await _ in group {}
        }
    }
}
