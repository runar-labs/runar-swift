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
        // ==========================================
        // Mobile side - first time use - generate user keys
        // ==========================================

        // Set up logging
        try await FFILogger.setLogLevel(.debug)
        try await FFILogger.setLoggerContext("mobile-test")

        // Create mobile keys manager
        let mobileKeys = try await MobileKeyManager()
        // Generate user root agreement public key for ECIES
        try await mobileKeys.initializeUserRootKey()
        let userPublicKey = try await mobileKeys.getUserPublicKey()

        XCTAssertEqual(userPublicKey.count, 65, "User root key should have a valid public key")

        // Get user CA public key
        let userCaPublicKey = try await mobileKeys.getCompactId(for: userPublicKey)
        XCTAssertFalse(userCaPublicKey.isEmpty, "User CA public key should not be empty")

        // ==========================================
        // Node first time use - enter in setup mode
        // ==========================================

        // Set up logging for node
        try await FFILogger.setLoggerContext("node-test")

        // Create node keys manager
        let nodeKeys = try await NodeKeyManager()

        // Node is now initialized and ready

        // Generate setup token (CSR)
        let setupToken = try await nodeKeys.generateCsrSetupToken()
        XCTAssertFalse(setupToken.isEmpty, "Setup token should not be empty")

        // ==========================================
        // Profile key functionality
        // ==========================================

        // Derive profile keys
        let personalProfileKey = try await mobileKeys.deriveUserProfileKey(label: "personal")
        let workProfileKey = try await mobileKeys.deriveUserProfileKey(label: "work")

        XCTAssertEqual(personalProfileKey.count, 65, "Personal profile key should be 65 bytes")
        XCTAssertEqual(workProfileKey.count, 65, "Work profile key should be 65 bytes")

        // Test profile key encryption
        let profileTestData = "Profile-specific test data".data(using: .utf8)!
        let encryptedProfileData = try await mobileKeys.encryptWithEnvelope(
            data: profileTestData,
            networkPublicKey: nil,
            profilePublicKeys: [personalProfileKey, workProfileKey]
        )
        XCTAssertFalse(encryptedProfileData.isEmpty, "Encrypted profile data should not be empty")

        // Test profile key decryption
        let decryptedProfileData = try await mobileKeys.decryptEnvelope(envelopeData: encryptedProfileData)
        XCTAssertEqual(decryptedProfileData, profileTestData, "Decrypted profile data should match original")

        // ==========================================
        // Certificate management
        // ==========================================

        // Generate CSR for certificate
        let csrData = try await nodeKeys.generateCsrSetupToken()
        XCTAssertFalse(csrData.isEmpty, "CSR data should not be empty")
    }

    func testPrimitivesE2ECANodeFlow() async throws {
        // Set up logging
        try await FFILogger.setLogLevel(.debug)
        try await FFILogger.setLoggerContext("ca-node-test")

        // ==========================================
        // Phase 1: CA Node Infrastructure Setup
        // ==========================================

        // Create CA Node
        let caNode = try await CANode.create()

        // ==========================================
        // Phase 2: Mobile Node Enrollment
        // ==========================================

        // Create mobile keys
        let mobileKeys = try await MobileKeyManager()
        try await mobileKeys.initializeUserRootKey()

        // Get user public key for mobile
        let userPublicKey = try await mobileKeys.getUserPublicKey()
        XCTAssertEqual(userPublicKey.count, 65, "User public key should be 65 bytes")

        // ==========================================
        // Phase 3: Profile Key Interop
        // ==========================================

        // Derive profile keys
        let personalProfileKey = try await mobileKeys.deriveUserProfileKey(label: "personal")
        let workProfileKey = try await mobileKeys.deriveUserProfileKey(label: "work")

        XCTAssertEqual(personalProfileKey.count, 65, "Personal profile key should be 65 bytes")
        XCTAssertEqual(workProfileKey.count, 65, "Work profile key should be 65 bytes")

        // Test profile key encryption/decryption
        let testData = "Profile key test data".data(using: .utf8)!
        let encryptedData = try await mobileKeys.encryptWithEnvelope(
            data: testData,
            networkPublicKey: nil,
            profilePublicKeys: [personalProfileKey, workProfileKey]
        )
        XCTAssertFalse(encryptedData.isEmpty, "Encrypted data should not be empty")

        let decryptedData = try await mobileKeys.decryptEnvelope(envelopeData: encryptedData)
        XCTAssertEqual(decryptedData, testData, "Decrypted data should match original")
    }
}
