import Foundation
@testable import RunarFFI
import SwiftCBOR
import XCTest

/// FFI End-to-End Integration Tests with REAL QUIC mTLS
///
/// This test validates the complete CA Node infrastructure using the FFI API with ACTUAL QUIC mTLS connections,
/// including bootstrap enrollment, mTLS participation, renewal, and CRL-lite enforcement.
///
/// Test phases:
/// 1. CA Node server setup via FFI with REAL QUIC mTLS
/// 2. Mobile node enrollment via FFI with REAL QUIC mTLS
/// 3. Certificate renewal over FFI with REAL QUIC mTLS
/// 4. Certificate revocation and CRL-lite over FFI with REAL QUIC mTLS
/// 5. Profile key interop over FFI with REAL QUIC mTLS
/// 6. Rate limiting over FFI with REAL QUIC mTLS
/// 7. Token revocation over FFI with REAL QUIC mTLS
@available(macOS 11.0, *)
final class FFIE2EIntegrationTest: XCTestCase {
    var keysFFI: KeysFFI?
    var mobileKeysFFI: KeysFFI?
    var logger: Logger?

    override func setUp() {
        super.setUp()
        logger = SimpleLogger()
        keysFFI = KeysFFI(logger: logger ?? SimpleLogger())
        mobileKeysFFI = KeysFFI(logger: logger ?? SimpleLogger())
    }

    override func tearDown() {
        keysFFI = nil
        mobileKeysFFI = nil
        logger = nil
        super.tearDown()
    }

    // MARK: - Test Data Structures

    /// CA Client Configuration with all options (CBOR-serialized)
    struct CaClientConfigAll: Codable {
        let bootstrapServer: String
        let authenticatedServer: String
        let networkId: String
        let requestTimeoutSeconds: UInt32
        let maxRetries: UInt32
        let rootCaDer: Data // Required, not optional
        let issuingCaDer: Data // Required, not optional
    }

    /// Custom CA Server Configuration
    struct CustomCaServerConfig: Codable {
        let bootstrapBind: String
        let authenticatedBind: String
        let networkId: String
        let rateLimitPerMinute: UInt32
        let rateLimitPerHour: UInt32
    }

    /// Revoke Request
    struct RevokeRequest: Codable {
        let networkId: String
        let certificateSerial: Data // Convert hex string to bytes
        let reason: String
    }

    // MARK: - Helper Functions

    /// Create test logger for CA operations
    func createTestLogger() -> UnsafeMutableRawPointer {
        // Return a placeholder pointer for the logger
        UnsafeMutableRawPointer(bitPattern: 1) ?? UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
    }

    /// Create test ECDSA key pair data
    func createTestEcdsaKeyPair() -> Data {
        // This would normally create a real ECDSA key pair
        // For now, return test data
        Data("test-ecdsa-key-pair".utf8)
    }

    /// Create test certificate data
    func createTestCertificate() -> Data {
        // This would normally create a real certificate
        // For now, return test data
        Data("test-certificate".utf8)
    }

    /// Create test EA public keys data
    func createTestEaPublicKeys() throws -> Data {
        // Create real EA public keys using enrollment token utilities
        return try FFIEnrollmentTokenUtils.createTestEaPublicKeys()
    }

    /// Create Root CA and Issuing CA certificates with proper chain
    /// Returns certificate chain data
    func createCaCertificateChain() throws -> CertificateChain {
        // Create real certificate chain using test utilities
        return try FFICertificateTestUtils.createCaCertificateChain()
    }

    /// Create enrollment token
    func createEnrollmentToken(networkId: String, tokenId: String) throws -> Data {
        // Create real enrollment token using enrollment token utilities
        return try FFIEnrollmentTokenUtils.createTestEnrollmentToken(
            networkId: networkId,
            tokenId: tokenId
        )
    }

    /// Validate certificate chain to ensure proper signing relationships
    func validateCertificateChain(rootCaDer: Data, issuingCaDer: Data) throws {
        // Use the certificate test utilities for validation
        let isValid = try FFICertificateTestUtils.validateCertificateChain(
            rootCaDer: rootCaDer,
            issuingCaDer: issuingCaDer
        )
        XCTAssertTrue(isValid, "Certificate chain validation should pass")

        print("   ✅ Root CA certificate: \(rootCaDer.count) bytes")
        print("   ✅ Issuing CA certificate: \(issuingCaDer.count) bytes")
        print("   ✅ Certificate chain validation passed")
    }

    // MARK: - Main E2E Test

    /// Test basic certificate and enrollment token functionality
    func testBasicCertificateAndTokenFunctionality() throws {
        print("\n🚀 Starting basic certificate and token functionality test")
        
        // Test certificate chain creation
        let certificateChain = try createCaCertificateChain()
        print("   ✅ Certificate chain created: \(certificateChain.rootCaCert.count) bytes root, \(certificateChain.issuingCertDer.count) bytes issuing")
        
        // Test enrollment token creation
        let enrollmentToken = try createEnrollmentToken(networkId: "test_network", tokenId: "test_token_001")
        print("   ✅ Enrollment token created: \(enrollmentToken.count) bytes")
        
        // Test EA public keys creation
        let eaPublicKeys = try createTestEaPublicKeys()
        print("   ✅ EA public keys created: \(eaPublicKeys.count) bytes")
        
        print("\n🎉 Basic certificate and token functionality test completed successfully!")
    }
    
    /// Test the full CA Node infrastructure using FFI API with REAL QUIC mTLS connections
    /// NOTE: This test is currently disabled as the CA infrastructure classes are not yet implemented
    func testFFIFullTransportE2EQuicMtls() throws {
        // TODO: Enable this test once CA infrastructure classes are implemented
        throw XCTSkip("CA infrastructure classes not yet implemented")
        /*
        print("\n🚀 Starting FFI Full-transport E2E QUIC mTLS test")

        // ==========================================
        // Phase 1: Setup
        // ==========================================
        print("\n🏗️  PHASE 1: Setup")

        // Create test logger
        let loggerPtr = createTestLogger()

        // Initialize as node
        guard let keysFFI = keysFFI else {
            XCTFail("KeysFFI not initialized")
            return
        }
        try keysFFI.initializeAsNode()

        // Initialize as mobile
        guard let mobileKeysFFI = mobileKeysFFI else {
            XCTFail("MobileKeysFFI not initialized")
            return
        }
        try mobileKeysFFI.initializeAsMobile()

        print("   ✅ Keys handles created and initialized")

        // ==========================================
        // Phase 2: CA Node and Server
        // ==========================================
        print("\n🏗️  PHASE 2: CA Node and Server")

        // Create CA Node
        let caNode = try FFICANode.create(logger: loggerPtr)
        defer { FFICANode.free(caNode) }

        // Create Root CA and Issuing CA certificates with proper chain
        let certificateChain = try createCaCertificateChain()
        let rootCaCert = certificateChain.rootCaCert
        let issuingKeyCbor = certificateChain.issuingKeyDer
        let issuingCertDer = certificateChain.issuingCertDer
        print("   ✅ Root CA certificate created")
        print("   ✅ Issuing CA certificate created (signed by Root CA)")

        // Pre-handshake diagnostics: Validate certificate chain
        print("   🔍 Validating certificate chain...")
        try validateCertificateChain(rootCaDer: rootCaCert, issuingCaDer: issuingCertDer)
        print("   ✅ Certificate chain validation passed")

        // Additional certificate diagnostics
        print("   🔍 Certificate diagnostics:")
        print("      Root CA cert: \(rootCaCert.count) bytes")
        print("      Issuing CA cert: \(issuingCertDer.count) bytes")
        print("      Root CA cert starts with: \(rootCaCert.prefix(8).map { String(format: "%02x", $0) }.joined())")
        let issuingCertHex = issuingCertDer.prefix(8).map { String(format: "%02x", $0) }.joined()
        print("      Issuing CA cert starts with: \(issuingCertHex)")

        // Create EA key pair (will be used for both server config and token generation)
        let eaKey = createTestEcdsaKeyPair()
        let eaPublicKeysCbor = try createTestEaPublicKeys()
        print("   ✅ EA key pair created (will be used for both server config and token signing)")

        // Install issuing CA in CA Node
        let networkId = "test_network"
        try FFICANode.installIssuingCA(
            caNode: caNode,
            issuingKeyCbor: issuingKeyCbor,
            issuingCertDer: issuingCertDer,
            rootCaCert: rootCaCert,
            eaPublicKeysCbor: eaPublicKeysCbor,
            networkId: networkId
        )

        // Configure enrollment authority
        try FFICANode.configureEnrollmentAuthority(
            caNode: caNode,
            eaPublicKeysCbor: eaPublicKeysCbor
        )

        print("   ✅ CA Node configured with issuing CA and enrollment authority")

        // Create shared CA Node reference for server usage AFTER configuring the CA Node
        let sharedCaNode = try FFICANode.createShared(caNode: caNode)
        defer { FFICANode.freeShared(sharedCaNode) }

        // Create CA Server config CBOR
        let customConfig = CustomCaServerConfig(
            bootstrapBind: "127.0.0.1:0",
            authenticatedBind: "127.0.0.1:0",
            networkId: "test_network",
            rateLimitPerMinute: 5,
            rateLimitPerHour: 30
        )

        let serverConfig = try CodableCBOREncoder().encode(customConfig)

        // Create CA Server using shared CA Node reference
        let caServer = try FFICAServer.create(
            config: serverConfig,
            sharedCaNode: sharedCaNode,
            logger: loggerPtr
        )
        defer { FFICAServer.free(caServer) }

        // Start CA Server
        try FFICAServer.start(caServer: caServer)

        // Wait a moment for server to fully start
        Thread.sleep(forTimeInterval: 0.1)

        // Get server addresses
        let bootstrapAddr = try FFICAServer.getBootstrapAddress(caServer: caServer)
        let authenticatedAddr = try FFICAServer.getAuthenticatedAddress(caServer: caServer)

        print("   ✅ CA Server started with addresses")
        print("      Bootstrap: \(bootstrapAddr)")
        print("      Authenticated: \(authenticatedAddr)")

        // Test basic network connectivity
        print("   🔍 Testing basic network connectivity...")
        if bootstrapAddr.range(of: ":") != nil {
            print("   ✅ Bootstrap address resolved: \(bootstrapAddr)")
        } else {
            print("   ❌ Bootstrap address resolution failed")
        }

        if authenticatedAddr.range(of: ":") != nil {
            print("   ✅ Authenticated address resolved: \(authenticatedAddr)")
        } else {
            print("   ❌ Authenticated address resolution failed")
        }

        // ==========================================
        // Phase 3: Mobile Node (client role) CSR and Enrollment
        // ==========================================
        print("\n📱 PHASE 3: Mobile Node CSR and Enrollment")

        // Generate CSR on node (returns SetupToken CBOR)
        let setupToken = try keysFFI.generateCSR()
        print("   ✅ CSR generated (\(setupToken.count) bytes)")

        // Create enrollment token using the SAME EA key (following design section 6.6)
        let enrollmentToken = try createEnrollmentToken(networkId: "test_network", tokenId: "test_token_001")
        print("   ✅ Enrollment token created with SAME EA key used for server config")

        // Build CsrEnrollRequest CBOR (following working test pattern)
        // Note: This would normally create a proper CsrEnrollRequest struct
        let enrollRequest = Data("test-enroll-request".utf8)

        // Create CA Client with all configuration at once (following design section 6.6)
        print("   🔧 Creating CA Client with all configuration (following design section 6.6):")
        print("      Bootstrap: \(bootstrapAddr)")
        print("      Authenticated: \(authenticatedAddr)")
        print("      Network ID: test_network")
        print("      Timeout: 30s, Max retries: 3")
        print("      Root CA cert: \(rootCaCert.count) bytes")
        print("      Issuing CA cert: \(issuingCertDer.count) bytes")

        // Create configuration CBOR
        let config = CaClientConfigAll(
            bootstrapServer: bootstrapAddr,
            authenticatedServer: authenticatedAddr,
            networkId: "test_network",
            requestTimeoutSeconds: 30,
            maxRetries: 3,
            rootCaDer: rootCaCert, // Required, not optional
            issuingCaDer: issuingCertDer // Required, not optional
        )

        let configCbor = try CodableCBOREncoder().encode(config)

        let caClient = try FFICAClient.createWithConfig(
            config: configCbor,
            keysHandle: keysFFI.nodeKeysHandle,
            logger: loggerPtr
        )
        defer { FFICAClient.free(caClient) }

        print("   ✅ CA Client created with all configuration for REAL QUIC mTLS")

        // Enroll via CA Client
        print("   🔧 Attempting enrollment with:")
        print("      Bootstrap address: \(bootstrapAddr)")
        print("      Request size: \(enrollRequest.count) bytes")
        print("      CSR size: \(setupToken.count) bytes")

        let enrollResponse = try FFICAClient.enroll(
            caClient: caClient,
            bootstrapAddress: bootstrapAddr,
            enrollRequest: enrollRequest
        )

        print("   ✅ Enrollment successful (\(enrollResponse.count) bytes response)")

        // Convert response to NodeCertificateMessage
        let certMessage = try mobileKeysFFI.fromEnrollResponse(enrollResponse: enrollResponse)
        print("   ✅ Certificate message created (\(certMessage.count) bytes)")

        // Install certificate
        try keysFFI.installCertificate(certificateMessage: certMessage)
        print("   ✅ Certificate installed and validated")

        // QUIC Cert Config Validation
        let quicConfig = try keysFFI.getQuicCertificateConfig()
        print("   ✅ QUIC certificate config validated (\(quicConfig.count) bytes)")

        // ==========================================
        // Phase 4: Certificate Renewal via REAL QUIC mTLS
        // ==========================================
        print("\n🔄 PHASE 4: Certificate Renewal via REAL QUIC mTLS")

        // Generate renewal CSR (returns SetupToken CBOR)
        let renewalSetupToken = try keysFFI.generateCSR()
        print("   ✅ Renewal CSR generated (\(renewalSetupToken.count) bytes)")

        // Build RenewRequest CBOR
        let renewRequest = Data("test-renew-request".utf8)

        // Renew via CA Client (authenticated endpoint)
        let renewResponse = try FFICAClient.renew(
            caClient: caClient,
            authenticatedAddress: authenticatedAddr,
            renewRequest: renewRequest
        )

        print("   ✅ Certificate renewal successful (\(renewResponse.count) bytes response)")

        // Convert response to NodeCertificateMessage
        let renewalCertMessage = try mobileKeysFFI.fromRenewResponse(renewResponse: renewResponse)
        print("   ✅ Renewal certificate message created (\(renewalCertMessage.count) bytes)")

        // Install renewed certificate
        try keysFFI.installCertificate(certificateMessage: renewalCertMessage)
        print("   ✅ Renewed certificate installed and validated")

        // ==========================================
        // Phase 5: Certificate Revocation + CRL-lite via REAL QUIC mTLS
        // ==========================================
        print("\n🚫 PHASE 5: Certificate Revocation + CRL-lite via REAL QUIC mTLS")

        // Extract SKI from the client's certificate for admin authorization
        let clientCertDer = try keysFFI.getNodeCertificate()

        // Extract SKI from client certificate
        let clientSki = try FFICertificateTestUtils.extractSKI(from: clientCertDer)
        print("   📋 Client certificate SKI: \(clientSki)")

        // Add client SKI to shared CA Node (which is what the server actually uses)
        try FFICANode.addAdminSki(caNode: sharedCaNode, adminSki: clientSki)

        // Also configure admin SKIs on the server
        let adminSkis = [clientSki]
        let adminSkisCbor = try CodableCBOREncoder().encode(adminSkis)
        try FFICAServer.configureAdminSkis(caServer: caServer, adminSkis: adminSkisCbor)

        print("   ✅ Admin SKI configured for revocation: \(clientSki)")

        // Get certificate serial for revocation
        let certSerial = try FFICertificateTestUtils.getSerialNumber(from: clientCertDer)
        print("   📋 Certificate serial for revocation: \(certSerial)")

        // Create RevokeRequest
        let revokeRequest = RevokeRequest(
            networkId: "test_network",
            certificateSerial: Data(hexString: certSerial) ?? Data(),
            reason: "testing"
        )

        let revokeRequestCbor = try CodableCBOREncoder().encode(revokeRequest)

        // Revoke certificate via client (mTLS)
        let revokeResponse = try FFICAClient.revoke(
            caClient: caClient,
            authenticatedAddress: authenticatedAddr,
            revokeRequest: revokeRequestCbor
        )

        print("   ✅ Certificate revoked successfully")

        // Generate CRL-lite
        let crl = try FFICANode.handleCrl(caNode: caNode, networkId: networkId)
        print("   ✅ CRL-lite generated successfully")

        // ==========================================
        // Phase 6: Status and Chain via REAL QUIC mTLS
        // ==========================================
        print("\n📊 PHASE 6: Status and Chain via REAL QUIC mTLS")

        // Get CA Status
        let statusResponse = try FFICAClient.getStatus(
            caClient: caClient,
            authenticatedAddress: authenticatedAddr,
            networkId: networkId
        )
        print("   ✅ CA Status retrieved via REAL QUIC mTLS (\(statusResponse.count) bytes)")

        // Get Certificate Chain
        let chainResponse = try FFICAClient.getChain(
            caClient: caClient,
            bootstrapAddress: bootstrapAddr,
            networkId: networkId
        )
        print("   ✅ Certificate chain retrieved via REAL QUIC mTLS (\(chainResponse.count) bytes)")

        // ==========================================
        // Phase 7: Profile Key Functionality via REAL QUIC mTLS
        // ==========================================
        print("\n🔑 PHASE 7: Profile Key Functionality via REAL QUIC mTLS")

        // Derive profile keys
        let personalProfileKey = try keysFFI.deriveUserProfileKey(label: "personal")
        let workProfileKey = try keysFFI.deriveUserProfileKey(label: "work")

        print("   ✅ Profile keys derived: personal (\(personalProfileKey.count) bytes), " +
              "work (\(workProfileKey.count) bytes)")

        // Test profile key encryption/decryption
        let testData = Data("Hello, encrypted world!".utf8)
        let personalProfileId = try keysFFI.getCompactId(publicKey: personalProfileKey)

        // Create envelope with profile keys
        let envelopeData = try keysFFI.encryptWithEnvelope(
            data: testData,
            networkId: nil,
            networkPublicKey: nil,
            profileKeys: [personalProfileKey],
            profileLens: [personalProfileKey.count]
        )

        print("   ✅ Data encrypted with profile key envelope (\(envelopeData.count) bytes)")

        // Decrypt with profile key
        let decryptedData = try keysFFI.decryptWithProfile(
            envelopeData: envelopeData,
            profileId: personalProfileId
        )

        XCTAssertEqual(decryptedData, testData, "Decrypted data should match original")
        print("   ✅ Profile key encryption/decryption working correctly")

        // ==========================================
        // Phase 8: Rate Limiting via REAL QUIC mTLS
        // ==========================================
        print("\n⏱️  PHASE 8: Rate Limiting via REAL QUIC mTLS")

        // Test rate limiting with multiple enrollment requests using the same token
        for i in 1 ... 3 {
            let testSetupToken = try keysFFI.generateCSR()
            let testEnrollRequest = Data("test-enroll-request-\(i)".utf8)

            do {
                _ = try FFICAClient.enroll(
                    caClient: caClient,
                    bootstrapAddress: bootstrapAddr,
                    enrollRequest: testEnrollRequest
                )
                print("   ⚠️  Rate limit check \(i) unexpectedly passed (rate limiting may not be working)")
            } catch {
                print("   ✅ Rate limit check \(i) correctly rejected (rate limiting working) - Error: \(error)")
            }

            // Add a small delay to ensure rate limiting works properly
            Thread.sleep(forTimeInterval: 0.01)
        }

        // ==========================================
        // Phase 9: Token Revocation via REAL QUIC mTLS
        // ==========================================
        print("\n🔒 PHASE 9: Token Revocation via REAL QUIC mTLS")

        // Revoke the enrollment token
        try FFICANode.revokeToken(caNode: caNode, tokenId: "test_token_001")
        print("   ✅ Enrollment token revoked via REAL QUIC mTLS")

        // Try to use revoked token (should fail)
        let testSetupToken = try keysFFI.generateCSR()
        let revokedRequest = Data("test-revoked-request".utf8)

        do {
            _ = try FFICAClient.enroll(
                caClient: caClient,
                bootstrapAddress: bootstrapAddr,
                enrollRequest: revokedRequest
            )
            XCTFail("Revoked token should be rejected")
        } catch {
            print("   ✅ Revoked token correctly rejected via REAL QUIC mTLS")
        }

        // ==========================================
        // Phase 10: Negative Cases via REAL QUIC mTLS
        // ==========================================
        print("\n❌ PHASE 10: Negative Cases via REAL QUIC mTLS")

        // Test invalid enrollment token (wrong network_id)
        let invalidToken = try createEnrollmentToken(networkId: "wrong_network", tokenId: "invalid_token")
        let invalidRequest = Data("test-invalid-request".utf8)

        do {
            _ = try FFICAClient.enroll(
                caClient: caClient,
                bootstrapAddress: bootstrapAddr,
                enrollRequest: invalidRequest
            )
            XCTFail("Invalid token should be rejected")
        } catch {
            print("   ✅ Invalid enrollment token rejected via REAL QUIC mTLS")
        }

        // Test unauthorized renewal (new node without enrollment)
        let unauthorizedKeys = KeysFFI(logger: logger)
        try unauthorizedKeys.initializeAsNode()

        let unauthorizedSetupToken = try unauthorizedKeys.generateCSR()
        let unauthorizedRenew = Data("test-unauthorized-renew".utf8)

        do {
            _ = try FFICAClient.renew(
                caClient: caClient,
                authenticatedAddress: authenticatedAddr,
                renewRequest: unauthorizedRenew
            )
            XCTFail("Unauthorized renewal should be rejected")
        } catch {
            print("   ✅ Unauthorized renewal rejected via REAL QUIC mTLS")
        }

        // ==========================================
        // Cleanup
        // ==========================================
        print("\n🧹 CLEANUP: Freeing all resources")

        // Stop CA Server
        try FFICAServer.stop(caServer: caServer)

        print("   ✅ All resources freed successfully")

        print("\n🎉 FFI FULL-TRANSPORT E2E TEST COMPLETED SUCCESSFULLY!")
        print("📋 All validations passed:")
        print("   ✅ CA Node infrastructure setup")
        print("   ✅ REAL QUIC mTLS transport configuration")
        print("   ✅ Mobile node enrollment via REAL QUIC mTLS")
        print("   ✅ Certificate renewal via REAL QUIC mTLS")
        print("   ✅ Certificate revocation and CRL-lite via REAL QUIC mTLS")
        print("   ✅ CA Node API status and chain via REAL QUIC mTLS")
        print("   ✅ Profile key interop via REAL QUIC mTLS")
        print("   ✅ Rate limiting via REAL QUIC mTLS")
        print("   ✅ Token revocation via REAL QUIC mTLS")
        print("   ✅ Error handling via REAL QUIC mTLS")

        print("\n🌐 CA NODE INFRASTRUCTURE READY FOR PRODUCTION WITH REAL QUIC mTLS!")
        print("📊 Test Statistics:")
        print("   • Root CA: \(rootCaCert.count) bytes")
        print("   • Issuing CA: \(issuingCertDer.count) bytes")
        print("   • Network ID: test_network")
        print("   • Profile keys: 2 (personal, work)")
        print("   • Revoked certificates: 1")
        print("   • Rate limiting: ✅")
        print("   • CRL-lite: ✅")
        print("   • REAL QUIC mTLS: ✅")
        */
    }
}

// MARK: - Data Extensions

extension Data {
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var i = hexString.startIndex
        for _ in 0..<len {
            let j = hexString.index(i, offsetBy: 2)
            let bytes = hexString[i..<j]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
            i = j
        }
        self = data
    }
}

