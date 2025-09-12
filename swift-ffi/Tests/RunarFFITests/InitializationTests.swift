@testable import RunarFFI
import XCTest

/// Initialization Tests
///
/// Tests for proper initialization, error handling, and manager type isolation.
/// Mirrors the initialization_test.rs from Rust.
final class InitializationTests: XCTestCase {
    
    // MARK: - Handle Creation Tests
    
    func testKeysHandleCreation() throws {
        let keys = KeysFFI()
        XCTAssertNotNil(keys, "KeysFFI handle should be created successfully")
    }
    
    func testInitAsMobileSuccess() throws {
        let keys = KeysFFI()
        XCTAssertNoThrow(try keys.initializeAsMobile(), "Should initialize as mobile successfully")
    }
    
    func testInitAsNodeSuccess() throws {
        let keys = KeysFFI()
        XCTAssertNoThrow(try keys.initializeAsNode(), "Should initialize as node successfully")
    }
    
    // MARK: - Re-initialization Tests
    
    func testInitAsMobileThenMobileAgain() throws {
        let keys = KeysFFI()
        try keys.initializeAsMobile()
        
        // Should throw when re-initializing (this is correct behavior)
        XCTAssertThrowsError(try keys.initializeAsMobile()) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError when re-initializing")
        }
    }
    
    func testInitAsNodeThenNodeAgain() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()
        
        // Should throw when re-initializing (this is correct behavior)
        XCTAssertThrowsError(try keys.initializeAsNode()) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError when re-initializing")
        }
    }
    
    func testInitAsMobileThenNodeFails() throws {
        let keys = KeysFFI()
        try keys.initializeAsMobile()
        
        // Should throw when trying to initialize as different type
        XCTAssertThrowsError(try keys.initializeAsNode()) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError when changing manager type")
        }
    }
    
    func testInitAsNodeThenMobileFails() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()
        
        // Should throw when trying to initialize as different type
        XCTAssertThrowsError(try keys.initializeAsMobile()) { error in
            XCTAssertTrue(error is FFIError, "Should throw FFIError when changing manager type")
        }
    }
    
    // MARK: - Function Access Tests
    
    func testMobileFunctionsRequireMobileInit() throws {
        let keys = KeysFFI()
        // Not initialized - should fail
        
        XCTAssertThrowsError(try keys.mobileInitializeUserRootKey()) { error in
            XCTAssertTrue(error is FFIError, "Mobile functions should require mobile initialization")
        }
    }
    
    func testMobileFunctionsFailWithNodeInit() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()
        
        XCTAssertThrowsError(try keys.mobileInitializeUserRootKey()) { error in
            XCTAssertTrue(error is FFIError, "Mobile functions should fail with node initialization")
        }
    }
    
    func testNodeFunctionsRequireNodeInit() throws {
        let keys = KeysFFI()
        // Not initialized - should fail
        
        XCTAssertThrowsError(try keys.nodeGetPublicKey()) { error in
            XCTAssertTrue(error is FFIError, "Node functions should require node initialization")
        }
    }
    
    func testNodeFunctionsFailWithMobileInit() throws {
        let keys = KeysFFI()
        try keys.initializeAsMobile()
        
        XCTAssertThrowsError(try keys.nodeGetPublicKey()) { error in
            XCTAssertTrue(error is FFIError, "Node functions should fail with mobile initialization")
        }
    }
    
    // MARK: - Function Success Tests
    
    func testMobileFunctionsWorkAfterMobileInit() throws {
        let keys = KeysFFI()
        try keys.initializeAsMobile()
        
        // Should not throw
        XCTAssertNoThrow(try keys.mobileInitializeUserRootKey(), "Mobile functions should work after mobile init")
        
        let publicKey = try keys.mobileGetUserPublicKey()
        XCTAssertFalse(publicKey.isEmpty, "Should be able to get user public key")
    }
    
    func testNodeFunctionsWorkAfterNodeInit() throws {
        let keys = KeysFFI()
        try keys.initializeAsNode()
        
        // Should not throw
        XCTAssertNoThrow(try keys.nodeGetPublicKey(), "Node functions should work after node init")
        XCTAssertNoThrow(try keys.nodeGetAgreementPublicKey(), "Node functions should work after node init")
        XCTAssertNoThrow(try keys.nodeGetNodeId(), "Node functions should work after node init")
        
        let publicKey = try keys.nodeGetPublicKey()
        XCTAssertFalse(publicKey.isEmpty, "Should be able to get node public key")
        
        let agreementKey = try keys.nodeGetAgreementPublicKey()
        XCTAssertFalse(agreementKey.isEmpty, "Should be able to get node agreement public key")
        
        let nodeId = try keys.nodeGetNodeId()
        XCTAssertFalse(nodeId.isEmpty, "Should be able to get node ID")
    }
    
    // MARK: - Error Code Tests
    
    func testErrorCodesAreUnique() throws {
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
        
        XCTAssertEqual(errorCodes.count, 11, "All error codes should be unique")
    }
    
    func testErrorMessagesAreHelpful() throws {
        let keys = KeysFFI()
        
        do {
            try keys.mobileInitializeUserRootKey()
            XCTFail("Should have thrown an error")
        } catch let error as FFIError {
            let message = error.localizedDescription
            XCTAssertFalse(message.isEmpty, "Error message should not be empty")
            XCTAssertTrue(message.contains("not initialized") || message.contains("wrong manager type"), 
                         "Error message should be helpful: \(message)")
        } catch {
            XCTFail("Should have thrown FFIError, got: \(error)")
        }
    }
}
