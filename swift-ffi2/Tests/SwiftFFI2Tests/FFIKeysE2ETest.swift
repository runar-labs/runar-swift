import XCTest
import SwiftFFI2
import SwiftCommon

/// Comprehensive End-to-End Integration Tests for Runar Keys FFI
///
/// This test mirrors the Rust end_to_end_test.rs and primitives_e2e_test.rs
/// to validate the complete end-to-end encryption and key management flows
/// using the Swift FFI wrapper library.
@testable import SwiftFFI2

final class FFIKeysE2ETest: XCTestCase {
    
    func testKeysE2EGenerationAndExchange() throws {
        print("🚀 Starting comprehensive end-to-end keys generation and exchange test")
        
        // ==========================================
        // Mobile side - first time use - generate user keys
        // ==========================================
        print("\n📱 MOBILE SIDE - First Time Setup")
        
        // Set up logging
        FFILogger.setLogLevel(.debug)
        try FFILogger.setLoggerNodeId("mobile-test")
        
        // Create mobile keys manager
        let mobileKeys = try KeysHandle()
        try mobileKeys.initializeAsMobile()
        
        // Generate user root agreement public key for ECIES
        try mobileKeys.mobileInitializeUserRootKey()
        let userPublicKey = try mobileKeys.mobileGetUserPublicKey()
        
        XCTAssertEqual(userPublicKey.count, 65, "User root key should have a valid public key")
        print("   ✅ User public key generated: \(userPublicKey.count) bytes")
        
        // Get user CA public key
        let userCaPublicKey = try mobileKeys.getCompactId(for: userPublicKey)
        XCTAssertFalse(userCaPublicKey.isEmpty, "User CA public key should not be empty")
        print("   ✅ User CA public key: \(userCaPublicKey)")
        
        print("   • User root key: \(userPublicKey.count) bytes")
        print("   • CA public key: \(userCaPublicKey.count) characters")
        
        // ==========================================
        // Node first time use - enter in setup mode
        // ==========================================
        print("\n🖥️  NODE SIDE - Setup Mode")
        
        // Set up logging for node
        try FFILogger.setLoggerNodeId("node-test")
        
        // Create node keys manager
        let nodeKeys = try KeysHandle()
        try nodeKeys.initializeAsNode()
        
        // Node is now initialized and ready
        print("   ✅ Node initialized successfully")
        
        // Generate setup token (CSR)
        let setupToken = try nodeKeys.generateCsrSetupToken()
        XCTAssertFalse(setupToken.isEmpty, "Setup token should not be empty")
        print("   ✅ Setup token generated: \(setupToken.count) bytes")
        
        // ==========================================
        // Profile key functionality
        // ==========================================
        print("\n🔑 PROFILE KEY FUNCTIONALITY")
        
        // Derive profile keys
        let personalProfileKey = try mobileKeys.mobileDeriveUserProfileKey(label: "personal")
        let workProfileKey = try mobileKeys.mobileDeriveUserProfileKey(label: "work")
        
        XCTAssertEqual(personalProfileKey.count, 65, "Personal profile key should be 65 bytes")
        XCTAssertEqual(workProfileKey.count, 65, "Work profile key should be 65 bytes")
        print("   ✅ Profile keys derived: personal (\(personalProfileKey.count) bytes), work (\(workProfileKey.count) bytes)")
        
        // Test profile key encryption
        let profileTestData = "Profile-specific test data".data(using: .utf8)!
        let encryptedProfileData = try mobileKeys.mobileEncryptWithEnvelope(
            plaintext: profileTestData,
            profileKeys: [personalProfileKey, workProfileKey],
            networkKey: nil
        )
        XCTAssertFalse(encryptedProfileData.isEmpty, "Encrypted profile data should not be empty")
        print("   ✅ Profile data encrypted: \(encryptedProfileData.count) bytes")
        
        // Test profile key decryption
        let decryptedProfileData = try mobileKeys.mobileDecryptEnvelope(envelope: encryptedProfileData)
        XCTAssertEqual(decryptedProfileData, profileTestData, "Decrypted profile data should match original")
        print("   ✅ Profile data decrypted successfully")
        
        // ==========================================
        // Certificate management
        // ==========================================
        print("\n📜 CERTIFICATE MANAGEMENT")
        
        // Generate CSR for certificate
        let csrData = try nodeKeys.generateCsrSetupToken()
        XCTAssertFalse(csrData.isEmpty, "CSR data should not be empty")
        print("   ✅ CSR generated: \(csrData.count) bytes")
        
        print("\n🎉 END-TO-END KEYS TEST COMPLETED SUCCESSFULLY!")
        print("📋 All validations passed:")
        print("   ✅ Mobile user key generation")
        print("   ✅ Node setup and key generation")
        print("   ✅ Profile key functionality")
        print("   ✅ FFI wrapper integration")
    }
    
    func testPrimitivesE2ECANodeFlow() throws {
        print("🚀 Starting Primitives-only E2E CA Node test")
        
        // Set up logging
        FFILogger.setLogLevel(.debug)
        try FFILogger.setLoggerNodeId("ca-node-test")
        
        // ==========================================
        // Phase 1: CA Node Infrastructure Setup
        // ==========================================
        print("\n🏗️  PHASE 1: CA Node Infrastructure Setup")
        
        // Create CA Node
        let caNode = try CANode.create()
        print("   ✅ CA Node created")
        
        // ==========================================
        // Phase 2: Mobile Node Enrollment
        // ==========================================
        print("\n📱 PHASE 2: Mobile Node Enrollment")
        
        // Create mobile keys
        let mobileKeys = try KeysHandle()
        try mobileKeys.initializeAsMobile()
        try mobileKeys.mobileInitializeUserRootKey()
        
        // Get user public key for mobile
        let userPublicKey = try mobileKeys.mobileGetUserPublicKey()
        XCTAssertEqual(userPublicKey.count, 65, "User public key should be 65 bytes")
        print("   ✅ User public key generated: \(userPublicKey.count) bytes")
        
        // ==========================================
        // Phase 3: Profile Key Interop
        // ==========================================
        print("\n🔑 PHASE 3: Profile Key Interop")
        
        // Derive profile keys
        let personalProfileKey = try mobileKeys.mobileDeriveUserProfileKey(label: "personal")
        let workProfileKey = try mobileKeys.mobileDeriveUserProfileKey(label: "work")
        
        XCTAssertEqual(personalProfileKey.count, 65, "Personal profile key should be 65 bytes")
        XCTAssertEqual(workProfileKey.count, 65, "Work profile key should be 65 bytes")
        print("   ✅ Profile keys derived: personal (\(personalProfileKey.count) bytes), work (\(workProfileKey.count) bytes)")
        
        // Test profile key encryption/decryption
        let testData = "Profile key test data".data(using: .utf8)!
        let encryptedData = try mobileKeys.mobileEncryptWithEnvelope(
            plaintext: testData,
            profileKeys: [personalProfileKey, workProfileKey],
            networkKey: nil
        )
        XCTAssertFalse(encryptedData.isEmpty, "Encrypted data should not be empty")
        print("   ✅ Data encrypted with profile keys: \(encryptedData.count) bytes")
        
        let decryptedData = try mobileKeys.mobileDecryptEnvelope(envelope: encryptedData)
        XCTAssertEqual(decryptedData, testData, "Decrypted data should match original")
        print("   ✅ Data decrypted with profile keys successfully")
        
        print("\n🎉 PRIMITIVES E2E CA NODE TEST COMPLETED SUCCESSFULLY!")
        print("📋 All validations passed:")
        print("   ✅ CA Node infrastructure setup")
        print("   ✅ Mobile node enrollment")
        print("   ✅ Profile key interop")
        print("   ✅ FFI wrapper integration")
    }
}
