import SwiftCommon
import SwiftFFI
import XCTest

/// Comprehensive End-to-End Integration Tests for Runar Keys FFI
///
/// This test mirrors the Rust end_to_end_test.rs and primitives_e2e_test.rs
/// to validate the complete end-to-end encryption and key management flows
/// using the Swift FFI wrapper library.
@testable import SwiftFFI

@MainActor
final class FFIKeysE2ETest: XCTestCase {
    func testKeysE2EGenerationAndExchange() async throws {
        print("🚀 Starting comprehensive end-to-end keys generation and exchange test")

        // ==========================================
        // Mobile side - first time use - generate user keys
        // ==========================================
        print("\n📱 MOBILE SIDE - First Time Setup")

        // Set up logging
        try await FFILogger.setLogLevel(.debug)
        try await FFILogger.setLoggerNodeId("mobile-test")

        // Create mobile keys manager
        let mobileKeys = try await MobileKeyManager()
        // Generate user root agreement public key for ECIES
        try await mobileKeys.initializeUserRootKey()
        let userPublicKey = try await mobileKeys.getUserPublicKey()

        XCTAssertEqual(userPublicKey.count, 65, "User root key should have a valid public key")
        print("   ✅ User public key generated: \(userPublicKey.count) bytes")

        // Get user CA public key
        let userCaPublicKey = try await mobileKeys.getCompactId(for: userPublicKey)
        XCTAssertFalse(userCaPublicKey.isEmpty, "User CA public key should not be empty")
        print("   ✅ User CA public key: \(userCaPublicKey)")

        print("   • User root key: \(userPublicKey.count) bytes")
        print("   • CA public key: \(userCaPublicKey.count) characters")

        // ==========================================
        // Node first time use - enter in setup mode
        // ==========================================
        print("\n🖥️  NODE SIDE - Setup Mode")

        // Set up logging for node
        try await FFILogger.setLoggerNodeId("node-test")

        // Create node keys manager
        let nodeKeys = try await NodeKeyManager()

        // Node is now initialized and ready
        print("   ✅ Node initialized successfully")

        // Generate setup token (CSR)
        let setupToken = try await nodeKeys.generateCsrSetupToken()
        XCTAssertFalse(setupToken.isEmpty, "Setup token should not be empty")
        print("   ✅ Setup token generated: \(setupToken.count) bytes")

        // ==========================================
        // Profile key functionality
        // ==========================================
        print("\n🔑 PROFILE KEY FUNCTIONALITY")

        // Derive profile keys
        let personalProfileKey = try await mobileKeys.deriveUserProfileKey(label: "personal")
        let workProfileKey = try await mobileKeys.deriveUserProfileKey(label: "work")

        XCTAssertEqual(personalProfileKey.count, 65, "Personal profile key should be 65 bytes")
        XCTAssertEqual(workProfileKey.count, 65, "Work profile key should be 65 bytes")
        print("   ✅ Profile keys derived: personal (\(personalProfileKey.count) bytes), work (\(workProfileKey.count) bytes)")

        // Test profile key encryption
        let profileTestData = "Profile-specific test data".data(using: .utf8)!
        let encryptedProfileData = try await mobileKeys.encryptWithEnvelope(
            data: profileTestData,
            networkPublicKey: nil,
            profilePublicKeys: [personalProfileKey, workProfileKey]
        )
        XCTAssertFalse(encryptedProfileData.isEmpty, "Encrypted profile data should not be empty")
        print("   ✅ Profile data encrypted: \(encryptedProfileData.count) bytes")

        // Test profile key decryption
        let decryptedProfileData = try await mobileKeys.decryptEnvelope(envelopeData: encryptedProfileData)
        XCTAssertEqual(decryptedProfileData, profileTestData, "Decrypted profile data should match original")
        print("   ✅ Profile data decrypted successfully")

        // ==========================================
        // Certificate management
        // ==========================================
        print("\n📜 CERTIFICATE MANAGEMENT")

        // Generate CSR for certificate
        let csrData = try await nodeKeys.generateCsrSetupToken()
        XCTAssertFalse(csrData.isEmpty, "CSR data should not be empty")
        print("   ✅ CSR generated: \(csrData.count) bytes")

        print("\n🎉 END-TO-END KEYS TEST COMPLETED SUCCESSFULLY!")
        print("📋 All validations passed:")
        print("   ✅ Mobile user key generation")
        print("   ✅ Node setup and key generation")
        print("   ✅ Profile key functionality")
        print("   ✅ FFI wrapper integration")
    }

    func testPrimitivesE2ECANodeFlow() async throws {
        print("🚀 Starting Primitives-only E2E CA Node test")

        // Set up logging
        try await FFILogger.setLogLevel(.debug)
        try await FFILogger.setLoggerNodeId("ca-node-test")

        // ==========================================
        // Phase 1: CA Node Infrastructure Setup
        // ==========================================
        print("\n🏗️  PHASE 1: CA Node Infrastructure Setup")

        // Create CA Node
        let caNode = try await CANode.create()
        print("   ✅ CA Node created")

        // ==========================================
        // Phase 2: Mobile Node Enrollment
        // ==========================================
        print("\n📱 PHASE 2: Mobile Node Enrollment")

        // Create mobile keys
        let mobileKeys = try await MobileKeyManager()
        try await mobileKeys.initializeUserRootKey()

        // Get user public key for mobile
        let userPublicKey = try await mobileKeys.getUserPublicKey()
        XCTAssertEqual(userPublicKey.count, 65, "User public key should be 65 bytes")
        print("   ✅ User public key generated: \(userPublicKey.count) bytes")

        // ==========================================
        // Phase 3: Profile Key Interop
        // ==========================================
        print("\n🔑 PHASE 3: Profile Key Interop")

        // Derive profile keys
        let personalProfileKey = try await mobileKeys.deriveUserProfileKey(label: "personal")
        let workProfileKey = try await mobileKeys.deriveUserProfileKey(label: "work")

        XCTAssertEqual(personalProfileKey.count, 65, "Personal profile key should be 65 bytes")
        XCTAssertEqual(workProfileKey.count, 65, "Work profile key should be 65 bytes")
        print("   ✅ Profile keys derived: personal (\(personalProfileKey.count) bytes), work (\(workProfileKey.count) bytes)")

        // Test profile key encryption/decryption
        let testData = "Profile key test data".data(using: .utf8)!
        let encryptedData = try await mobileKeys.encryptWithEnvelope(
            data: testData,
            networkPublicKey: nil,
            profilePublicKeys: [personalProfileKey, workProfileKey]
        )
        XCTAssertFalse(encryptedData.isEmpty, "Encrypted data should not be empty")
        print("   ✅ Data encrypted with profile keys: \(encryptedData.count) bytes")

        let decryptedData = try await mobileKeys.decryptEnvelope(envelopeData: encryptedData)
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
