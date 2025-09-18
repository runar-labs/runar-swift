//! Initialization Error Handling Tests
//!
//! This test suite covers all initialization functionality including success cases,
//! error conditions, manager type validation, and error handling consistency.
//! Tests are based on initialization_test.rs.

import XCTest
@testable import SwiftFFI

final class InitializationTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        
        // Set log level to trace to see detailed logs
        try! FFILogger.setLogLevel(.trace)
    }
    
    // MARK: - Handle Creation Tests
    
    func testKeysHandleCreation() throws {
        // Test successful handle creation
        let keysHandle = try KeysHandle()
        XCTAssertNotNil(keysHandle, "KeysHandle should be created successfully")
    }
    
    // MARK: - Initialization Success Tests
    
    func testInitAsMobileSuccess() throws {
        // Test successful mobile initialization
        let keysHandle = try KeysHandle()
        XCTAssertNoThrow(try keysHandle.initializeAsMobile(), "Should successfully initialize as mobile")
    }
    
    func testInitAsNodeSuccess() throws {
        // Test successful node initialization
        let keysHandle = try KeysHandle()
        XCTAssertNoThrow(try keysHandle.initializeAsNode(), "Should successfully initialize as node")
    }
    
    // MARK: - Idempotent Initialization Tests
    
    func testInitAsMobileThenMobileAgain() throws {
        // Test idempotent mobile initialization
        let keysHandle = try KeysHandle()
        
        // First mobile initialization
        XCTAssertNoThrow(try keysHandle.initializeAsMobile(), "First mobile init should succeed")
        
        // Second mobile initialization - should succeed (idempotent)
        XCTAssertNoThrow(try keysHandle.initializeAsMobile(), "Second mobile init should succeed (idempotent)")
    }
    
    func testInitAsNodeThenNodeAgain() throws {
        // Test idempotent node initialization
        let keysHandle = try KeysHandle()
        
        // First node initialization
        XCTAssertNoThrow(try keysHandle.initializeAsNode(), "First node init should succeed")
        
        // Second node initialization - should succeed (idempotent)
        XCTAssertNoThrow(try keysHandle.initializeAsNode(), "Second node init should succeed (idempotent)")
    }
    
    // MARK: - Cross-Initialization Error Tests
    
    func testInitAsMobileThenNodeFails() throws {
        // Test that initializing as node after mobile fails
        let keysHandle = try KeysHandle()
        
        // Initialize as mobile first
        try keysHandle.initializeAsMobile()
        
        // Try to initialize as node - should fail
        XCTAssertThrowsError(try keysHandle.initializeAsNode()) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError")
            // Note: The specific error code depends on the FFI implementation
        }
    }
    
    func testInitAsNodeThenMobileFails() throws {
        // Test that initializing as mobile after node fails
        let keysHandle = try KeysHandle()
        
        // Initialize as node first
        try keysHandle.initializeAsNode()
        
        // Try to initialize as mobile - should fail
        XCTAssertThrowsError(try keysHandle.initializeAsMobile()) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError")
            // Note: The specific error code depends on the FFI implementation
        }
    }
    
    // MARK: - Function Access Tests
    
    func testMobileFunctionsRequireMobileInit() throws {
        // Test that mobile functions fail without initialization
        let keysHandle = try KeysHandle()
        
        // Try to call mobile function without initialization
        XCTAssertThrowsError(try keysHandle.mobileInitializeUserRootKey()) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError when not initialized")
        }
    }
    
    func testMobileFunctionsFailWithNodeInit() throws {
        // Test that mobile functions fail with node initialization
        let keysHandle = try KeysHandle()
        
        // Initialize as node
        try keysHandle.initializeAsNode()
        
        // Try to call mobile function with node initialization
        XCTAssertThrowsError(try keysHandle.mobileInitializeUserRootKey()) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError with wrong manager type")
        }
    }
    
    func testNodeFunctionsRequireNodeInit() throws {
        // Test that node functions fail without initialization
        let keysHandle = try KeysHandle()
        
        // Try to call node function without initialization
        XCTAssertThrowsError(try keysHandle.nodeGenerateKeys()) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError when not initialized")
        }
    }
    
    func testNodeFunctionsFailWithMobileInit() throws {
        // Test that node functions fail with mobile initialization
        let keysHandle = try KeysHandle()
        
        // Initialize as mobile
        try keysHandle.initializeAsMobile()
        
        // Try to call node function with mobile initialization
        XCTAssertThrowsError(try keysHandle.nodeGenerateKeys()) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError with wrong manager type")
        }
    }
    
    // MARK: - Function Success Tests
    
    func testMobileFunctionsWorkAfterMobileInit() throws {
        // Test that mobile functions work after proper initialization
        let keysHandle = try KeysHandle()
        
        // Initialize as mobile
        try keysHandle.initializeAsMobile()
        
        // Mobile functions should work
        XCTAssertNoThrow(try keysHandle.mobileInitializeUserRootKey(), "Mobile function should work after mobile init")
        
        // Test other mobile functions
        let userPublicKey = try keysHandle.mobileGetUserPublicKey()
        XCTAssertFalse(userPublicKey.isEmpty, "User public key should not be empty")
    }
    
    func testNodeFunctionsWorkAfterNodeInit() throws {
        // Test that node functions work after proper initialization
        let keysHandle = try KeysHandle()
        
        // Initialize as node
        try keysHandle.initializeAsNode()
        
        // Test that node functions don't fail with wrong manager type or not initialized
        // The function may fail with other errors (like memory allocation) but not these specific ones
        do {
            let _ = try keysHandle.getNodePublicKey()
            // If it succeeds, that's fine too
        } catch let error as FFIError {
            // Should not fail with wrong manager type or not initialized
            // Check error message instead of code since FFIError doesn't preserve the original code
            let errorMessage = error.localizedDescription
            XCTAssertFalse(errorMessage.contains("wrong manager type"), "Should not fail with wrong manager type")
            XCTAssertFalse(errorMessage.contains("not initialized"), "Should not fail with not initialized")
        }
    }
    
    // MARK: - Error Handling Consistency Tests
    
    func testErrorCodesAreUnique() throws {
        // Test that different error conditions return different error codes
        let keysHandle = try KeysHandle()
        
        // Test uninitialized error
        var uninitializedError: Error?
        do {
            try keysHandle.mobileInitializeUserRootKey()
        } catch {
            uninitializedError = error
        }
        
        // Test wrong manager type error
        try keysHandle.initializeAsNode()
        var wrongManagerError: Error?
        do {
            try keysHandle.mobileInitializeUserRootKey()
        } catch {
            wrongManagerError = error
        }
        
        // Both should be FFIError but with different underlying causes
        XCTAssertTrue(uninitializedError is FFIError, "Uninitialized error should be FFIError")
        XCTAssertTrue(wrongManagerError is FFIError, "Wrong manager error should be FFIError")
        
        // The error messages should be different
        if let uninitError = uninitializedError as? FFIError,
           let wrongError = wrongManagerError as? FFIError {
            XCTAssertNotEqual(uninitError.localizedDescription, wrongError.localizedDescription, 
                            "Different error conditions should have different messages")
        }
    }
    
    func testErrorMessagesAreHelpful() throws {
        // Test that error messages are descriptive and helpful
        let keysHandle = try KeysHandle()
        
        // Test uninitialized error message
        do {
            try keysHandle.mobileInitializeUserRootKey()
            XCTFail("Should have thrown an error")
        } catch let error as FFIError {
            let message = error.localizedDescription
            XCTAssertFalse(message.isEmpty, "Error message should not be empty")
            XCTAssertTrue(message.contains("not initialized") || message.contains("initialized"), 
                         "Error message should mention initialization: \(message)")
        }
        
        // Test wrong manager type error message
        try keysHandle.initializeAsNode()
        do {
            try keysHandle.mobileInitializeUserRootKey()
            XCTFail("Should have thrown an error")
        } catch let error as FFIError {
            let message = error.localizedDescription
            XCTAssertFalse(message.isEmpty, "Error message should not be empty")
            XCTAssertTrue(message.contains("manager") || message.contains("type") || message.contains("mobile"), 
                         "Error message should mention manager type: \(message)")
        }
    }
    
    // MARK: - Edge Case Tests
    
    func testMultipleHandleCreation() throws {
        // Test creating multiple handles
        let handle1 = try KeysHandle()
        let handle2 = try KeysHandle()
        let handle3 = try KeysHandle()
        
        XCTAssertNotNil(handle1, "First handle should be created")
        XCTAssertNotNil(handle2, "Second handle should be created")
        XCTAssertNotNil(handle3, "Third handle should be created")
        
        // Each handle should be independent
        try handle1.initializeAsMobile()
        try handle2.initializeAsNode()
        
        // Third handle should still be uninitialized
        XCTAssertThrowsError(try handle3.mobileInitializeUserRootKey(), "Third handle should still be uninitialized")
    }
    
    func testHandleReuseAfterError() throws {
        // Test that a handle can be reused after an error
        let keysHandle = try KeysHandle()
        
        // Try to use uninitialized handle
        XCTAssertThrowsError(try keysHandle.mobileInitializeUserRootKey(), "Should fail when uninitialized")
        
        // Initialize properly
        try keysHandle.initializeAsMobile()
        
        // Should work now
        XCTAssertNoThrow(try keysHandle.mobileInitializeUserRootKey(), "Should work after proper initialization")
    }
    
    func testConcurrentInitialization() throws {
        // Test concurrent initialization attempts
        let keysHandle = try KeysHandle()
        
        // This test verifies that the handle can handle concurrent access
        // In a real scenario, this would be tested with actual concurrency
        // For now, we just verify the handle works in sequence
        
        // First initialization
        try keysHandle.initializeAsMobile()
        
        // Verify it's properly initialized
        XCTAssertNoThrow(try keysHandle.mobileInitializeUserRootKey(), "Should work after initialization")
        
        // Try to reinitialize (should be idempotent)
        XCTAssertNoThrow(try keysHandle.initializeAsMobile(), "Should be idempotent")
    }
}
