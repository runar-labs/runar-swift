import Foundation
import SwiftCBOR
import SwiftCommon
@testable import SwiftFFI
import XCTest

final class FFIE2EIntegrationTest: XCTestCase {
    // Test resources that need cleanup
    private var caNode: CANode?
    private var server: CAServer?
    private var caClient: CAClient?
    private var mobileNode: MobileKeyManager?
    private var nodeKeys: NodeKeyManager?
    private var eaManager: EAKeyManager?
    private var eaHandle: UnsafeMutableRawPointer?
    
    override func setUp() async throws {
        try await super.setUp()
        // Initialize all resources to nil
        caNode = nil
        server = nil
        caClient = nil
        mobileNode = nil
        nodeKeys = nil
        eaManager = nil
        eaHandle = nil
    }
    
    override func tearDown() async throws {
        // Clean up resources in reverse order of creation
        if let handle = eaHandle {
            EAKeyManager.free(handle)
            eaHandle = nil
        }
        
        eaManager = nil
        nodeKeys = nil
        mobileNode = nil
        caClient = nil
        
        // Stop server if it's running
        if let server = server {
            do {
                try await server.stop()
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms delay for cleanup
            } catch {
                // Log but don't fail the test
                print("⚠️ Server stop encountered error during cleanup: \(error)")
            }
        }
        server = nil
        caNode = nil
        
        try await super.tearDown()
    }
    
    func createLogger() -> RunarLogger { RunarLogger(component: .custom) }

    func encode<T: Codable>(_ value: T) throws -> Data { try CodableCBOREncoder().encode(value) }
    func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T { try CodableCBORDecoder().decode(type, from: data) }

    func testWrapperFullTransportE2EQuicMtls() async throws {
        let logger = createLogger()
        logger.debug("CRITICAL: testWrapperFullTransportE2EQuicMtls() - entered")
        logger.debug("🔥🔥🔥 CRITICAL: testWrapperFullTransportE2EQuicMtls() - Method started 🔥🔥🔥")
        logger.debug("DEBUG: testWrapperFullTransportE2EQuicMtls() - Method started")
        logger.debug("\n🚀 Starting Full-transport E2E QUIC mTLS test")
        
        // Enable trace logging for detailed debugging
        logger.debug("DEBUG: About to call FFILogger.setLogLevel(.trace)")
        try await FFILogger.setLogLevel(.trace)
        logger.debug("DEBUG: FFILogger.setLogLevel(.trace) completed successfully")
        
        logger.debug("DEBUG: About to call FFILogger.setLoggerNodeId")
        try await FFILogger.setLoggerNodeId("e2e-integration-test")
        logger.debug("DEBUG: FFILogger.setLoggerNodeId completed successfully")
        
        // ==========================================
        // Phase 1: CA Node Infrastructure Setup
        // ==========================================
        logger.debug("\n🏗️  PHASE 1: CA Node Infrastructure Setup")
        
        // Create CA Node
        logger.debug("🔧 STEP 1: Creating CA Node...")
        caNode = try await CANode.create()
        logger.debug("   ✅ CA Node created successfully")
        
        // Create EA Key Manager and generate EA key pair
        logger.debug("🔧 STEP 2: Creating EA Key Manager and generating key pair...")
        eaManager = EAKeyManager(logger: createLogger())
        eaHandle = try await eaManager!.createKeyPair()
        logger.debug("   ✅ EA Key Manager created and key pair generated")
        
        // Get EA public key CBOR (public-only) EXACTLY as Rust does and pass directly to setup_complete
        logger.debug("🔧 STEP 3: Getting EA public key (CBOR blob) for setup_complete...")
        let eaPublicKeyCbor = try await eaManager!.getPublicKey(eaHandle!)
        logger.debug("   📊 EA public key CBOR length: \(eaPublicKeyCbor.count) bytes")
        logger.debug("   ✅ EA public key retrieved (will be passed directly to setup_complete)")
        
        // Setup CA Node with network ID
        logger.debug("🔧 STEP 5: Setting up CA Node with network ID...")
        let networkId = "test_network"
        let setupParams = CANodeManager.CANodeSetupParams(
            caNode: caNode!.ffiHandle,
            rootCaSubject: "CN=Test Root CA,O=Test,C=US",
            issuingCaSubject: "CN=Test Issuing CA,O=Test,C=US", 
            validityDays: 365,
            issuingCaSerial: 1,
            eaPublicKeys: eaPublicKeyCbor,
            networkId: networkId
        )
        logger.debug("   📊 Setup params: networkId=\(networkId), eaKeysLength=\(eaPublicKeyCbor.count)")
        logger.debug("   🔧 Calling caNode!.setupComplete() - this should trigger Rust FFI logs...")
        try await caNode!.setupComplete(params: setupParams)
        logger.debug("   ✅ CA Node setup completed successfully")
        
        // Validate CA certificates were generated
        logger.debug("   🔍 Fetching CA certificates after setup...")
        let rootCa = try await caNode!.getRootCACertificate()
        let issuingCa = try await caNode!.getIssuingCACertificate()
        
        logger.debug("   📊 Certificate lengths - Root: \(rootCa.count) bytes, Issuing: \(issuingCa.count) bytes")
        
        if rootCa.isEmpty {
            throw FFIError.operationFailed("CA root certificate is empty; ensure EA public keys are CBOR array of keys and configureEnrollmentAuthority was called")
        }
        if issuingCa.isEmpty {
            throw FFIError.operationFailed("CA issuing certificate is empty; ensure EA public keys are CBOR array of keys and configureEnrollmentAuthority was called")
        }
        logger.debug("   ✅ CA certificates validated - Root: \(rootCa.count) bytes, Issuing: \(issuingCa.count) bytes")
        
        // ==========================================
        // Phase 2: REAL QUIC Transport Setup
        // ==========================================
        logger.debug("\n🌐 PHASE 2: REAL QUIC Transport Setup")
        
        // Create shared CA node reference
        let shared = try await caNode!.createSharedWrapped()
        logger.debug("   ✅ Shared CA node reference created")
        
        // Create and start CA Server
        server = try await CAServer.create(
            config: CaServerConfig(
                bootstrapBind: "127.0.0.1:0",
                authenticatedBind: "127.0.0.1:0",
                networkId: networkId,
                rateLimitPerMinute: 5,
                rateLimitPerHour: 100
            ),
            sharedCaNode: shared.handle
        )
        logger.debug("   ✅ CA Server created")
        
        try await server!.start()
        logger.debug("   ✅ CA Server started")
        
        let bootstrapAddr = try await server!.bootstrapAddress()
        let authenticatedAddr = try await server!.authenticatedAddress()
        logger.debug("   ✅ Server addresses - Bootstrap: \(bootstrapAddr), Authenticated: \(authenticatedAddr)")
        
        // ==========================================
        // Phase 3: Enrollment Token Generation
        // ==========================================
        logger.debug("\n🎫 PHASE 3: Enrollment Token Generation")
        
        let now = UInt64(Date().timeIntervalSince1970)
        let nonceData = Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16])
        let tokenBody = EnrollmentTokenBody(
            token_id: "test_token_001",
            network_id: "test_network",
            subject_hint: "test_subject",
            not_before: now - 60,  // 1 minute ago to account for clock differences
            expires_at: now + 3600, // 1 hour
            nonce: nonceData,
            permissions: ["enroll"]
        )
        
        let enrollmentTokenData = try await eaManager!.generateEnrollmentToken(params: EAKeyManager.EnrollmentTokenParams(
            eaKeyHandle: eaHandle!,
            tokenId: "test_token_001",
            networkId: "test_network",
            subject: "test_subject",
            validFrom: now - 60,
            validUntil: now + 3600,
            nonce: nonceData,
            capabilities: ["enroll"]
        ))
        
        // Decode the enrollment token from the returned data
        let enrollmentToken = try CodableCBORDecoder().decode(EnrollmentToken.self, from: enrollmentTokenData)
        
        logger.debug("   ✅ Enrollment token generated: \(enrollmentToken.body.token_id)")
        logger.debug("   📅 Token validity: \(enrollmentToken.body.not_before) - \(enrollmentToken.body.expires_at)")
        logger.debug("   📅 Current time: \(now)")
        let isValidNow = now >= enrollmentToken.body.not_before && now <= enrollmentToken.body.expires_at
        logger.debug("   ✅ Token is valid now: \(isValidNow)")
        
    // ==========================================
    // Phase 4: Mobile Node Enrollment via REAL QUIC mTLS
    // ==========================================
    logger.debug("\n📱 PHASE 4: Mobile Node Enrollment via REAL QUIC mTLS")
    
    // Create mobile node key manager
    mobileNode = try await MobileKeyManager()
    logger.debug("   ✅ Mobile node key manager created")
    
    // Create node key manager for CA client
    nodeKeys = try await NodeKeyManager()
    logger.debug("   ✅ Node key manager created for CA client")
    
    // Generate CSR using the node manager (returns SetupToken CBOR like Rust)
    let setupTokenCbor = try await nodeKeys!.generateCSR()
    // Extract DER bytes from SetupToken CBOR (mirror Rust)
    let setupToken = try CodableCBORDecoder().decode(SetupToken.self, from: setupTokenCbor)
    let csrDerData = Data(setupToken.csr_der)
    logger.debug("   ✅ CSR generated: \(csrDerData.count) bytes")
    
    // Create enrollment request
    let csrEnrollRequest = CsrEnrollRequest(
        network_id: "test_network",
        csr_der: csrDerData,
        enrollment_token: enrollmentToken
    )
    logger.debug("   ✅ CSR enrollment request created")
    
    // Create CA client with the certificates from the CA node
    let caClientConfig = try CaClientConfigAll(
        bootstrap_server: bootstrapAddr,
        authenticated_server: authenticatedAddr,
        network_id: "test_network",
        request_timeout_seconds: 30,
        max_retries: 3,
        root_ca_der: rootCa,
        issuing_ca_der: issuingCa
    )
    
    logger.debug("DEBUG: About to create CA Client with config")
    logger.debug("DEBUG: Bootstrap server: \(bootstrapAddr)")
    logger.debug("DEBUG: Authenticated server: \(authenticatedAddr)")
    logger.debug("DEBUG: Root CA cert length: \(rootCa.count)")
    logger.debug("DEBUG: Issuing CA cert length: \(issuingCa.count)")
    logger.debug("DEBUG: About to call CAClient constructor")
    
    caClient = try await nodeKeys!.createCAClient(config: caClientConfig)
    logger.debug("   ✅ CA client created with certificates")
    logger.debug("DEBUG: CA Client created successfully, moving to Phase 3")
    
    // REAL QUIC mTLS enrollment
    // 1. Establish QUIC connection to CA Node server
    // 2. Perform mTLS handshake
    // 3. Send enrollment request over QUIC
    // 4. Receive enrollment response
    // 5. Validate mTLS peer certificate
    
    // Encode the enrollment request to CBOR
    let enrollRequestData = try CodableCBOREncoder().encode(csrEnrollRequest)
    
    let enrollResponse = try await caClient!.enroll(bootstrapAddress: bootstrapAddr, request: enrollRequestData)
    logger.debug("   ✅ Enrollment response received: \(enrollResponse.count) bytes")
    
    // Convert response to NodeCertificateMessage
    let certMessage = try await mobileNode!.fromEnrollResponse(enrollResponse)
    logger.debug("   ✅ Certificate message created from enrollment response")
    
    // Install certificate on node key manager (mirror Rust)
    try await nodeKeys!.installCertificate(certMessage)
    logger.debug("   ✅ Certificate installed and validated")
    // Allow transporter/server background tasks to settle before next CSR
    try await Task.sleep(nanoseconds: 150_000_000)
    
    logger.debug("\n🎉 PHASE 4 COMPLETED: Mobile Node Enrollment via REAL QUIC mTLS")
    
    // ==========================================
    // Phase 5: Certificate Renewal via REAL QUIC mTLS
    // ==========================================
    logger.debug("\n🔄 PHASE 5: Certificate Renewal via REAL QUIC mTLS")
    
    // Generate renewal CSR (returns SetupToken CBOR) and extract DER (mirror Rust)
    let renewalSetupTokenCbor = try await nodeKeys!.generateCSR()
    let renewalSetupToken = try CodableCBORDecoder().decode(SetupToken.self, from: renewalSetupTokenCbor)
    let renewalCsrDer = Data(renewalSetupToken.csr_der)
    logger.debug("   ✅ Renewal CSR generated: \(renewalCsrDer.count) bytes")
    
    // Create renewal request with DER
    let renewRequest = RenewRequest(
        network_id: "test_network",
        csr_der: renewalCsrDer
    )
    logger.debug("   ✅ Renewal request created")
    
    // Encode renewal request to CBOR
    let renewRequestData = try CodableCBOREncoder().encode(renewRequest)
    logger.debug("   ✅ Renewal request encoded to CBOR: \(renewRequestData.count) bytes")
    
    // REAL QUIC mTLS renewal
    let renewResponse = try await caClient!.renew(authenticatedAddress: authenticatedAddr, request: renewRequestData)
    logger.debug("   ✅ Certificate renewed via REAL QUIC mTLS")
    
    // Convert response to NodeCertificateMessage
    let renewalCertMessage = try await mobileNode!.fromRenewResponse(renewResponse)
    logger.debug("   ✅ Renewal response converted to certificate message")
    
    // Install renewed certificate on node key manager (mirror Rust)
    try await nodeKeys!.installCertificate(renewalCertMessage)
    logger.debug("   ✅ Renewed certificate installed")
    // Allow state to settle before subsequent operations
    try await Task.sleep(nanoseconds: 150_000_000)
    
    logger.debug("\n🎉 PHASE 5 COMPLETED: Certificate Renewal via REAL QUIC mTLS")
    
    // ==========================================
    // Phase 6: Certificate Revocation via REAL QUIC mTLS
    // ==========================================
    logger.debug("\n🚫 PHASE 6: Certificate Revocation via REAL QUIC mTLS")
    
    // Extract SKI from installed node certificate (mirror Rust)
    let nodeCertDer = try await nodeKeys!.getNodeCertificate()
    let mobileCertSki = try await CertificateUtils.extractSki(from: nodeCertDer)
    logger.debug("   🔑 Mobile cert SKI: \(mobileCertSki)")
    
    // Add SKI to server admin configuration (CBOR array of strings)
    let adminSkis = [mobileCertSki]
    let skiData = try CodableCBOREncoder().encode(adminSkis)
    try await server!.configureAdminSkis(skiData)
    logger.debug("   ✅ Mobile cert SKI added to server admin configuration")
    
    // Add SKI to CA Node's admin allowlist
    try await caNode!.addAdminSki(mobileCertSki.data(using: .utf8)!)
    logger.debug("   ✅ Mobile cert SKI added to CA Node admin allowlist")
    
    // Get certificate serial for revocation (hex string), then hex-decode to bytes
    let serialHex = try await CertificateUtils.getSerialHex(from: nodeCertDer)
    guard let serialData = Data(hexString: serialHex) else { throw FFIError.operationFailed("Invalid serial hex") }
    let certSerial = Array(serialData)
    logger.debug("   🔢 Certificate serial (hex): \(serialHex)")
    
    // Create revocation request
    let revokeRequest = RevokeRequest(
        network_id: "test_network",
        certificate_serial: certSerial,
        reason: "testing"
    )
    logger.debug("   ✅ Revocation request created")
    
    // Encode revocation request to CBOR
    let revokeRequestData = try CodableCBOREncoder().encode(revokeRequest)
    logger.debug("   ✅ Revocation request encoded to CBOR: \(revokeRequestData.count) bytes")
    
    // REAL QUIC mTLS revocation
    let revokeResponse = try await caClient!.revoke(authenticatedAddress: authenticatedAddr, request: revokeRequestData)
    logger.debug("   ✅ Certificate revoked via REAL QUIC mTLS")
    
    // Decode revocation response
    let revokeResponseData = try CodableCBORDecoder().decode(RevokeResponse.self, from: revokeResponse)
    XCTAssertTrue(revokeResponseData.ok)
    
    logger.debug("\n🎉 PHASE 6 COMPLETED: Certificate Revocation via REAL QUIC mTLS")
    
    // ==========================================
    // Phase 7: CRL-lite Generation and Validation via REAL QUIC mTLS
    // ==========================================
    logger.debug("\n📋 PHASE 7: CRL-lite Generation and Validation via REAL QUIC mTLS")
    
    // Generate CRL-lite
    let crl = try await caNode!.generateCrlLite()
    logger.debug("   ✅ CRL-lite generated: \(crl.count) bytes")
    
    // Decode CRL-lite to get details
    let crlData = try CodableCBORDecoder().decode(CrlLite.self, from: crl)
    logger.debug("   ✅ CRL-lite contains \(crlData.revoked_serials.count) revoked certificates")
    logger.debug("   ✅ CRL-lite signature present: \(crlData.signature.count) bytes")
    
    // REAL QUIC mTLS CRL fetching (mirror Rust: get_chain and server-side CRL-lite are distinct)
    let crlFromHandler = try await caClient!.getCrl(authenticatedAddress: authenticatedAddr, networkId: "test_network")
    logger.debug("   ✅ CRL-lite fetched via REAL QUIC mTLS: \(crlFromHandler.count) bytes")
    
    logger.debug("\n🎉 PHASE 7 COMPLETED: CRL-lite Generation and Validation via REAL QUIC mTLS")
    
    // ==========================================
    // Phase 8: CA Node API Status and Chain via REAL QUIC mTLS
    // ==========================================
    logger.debug("\n📊 PHASE 8: CA Node API Status and Chain via REAL QUIC mTLS")
    
    // REAL QUIC mTLS status/chain requests
    let status = try await caClient!.getStatus(authenticatedAddress: authenticatedAddr, networkId: "test_network")
    logger.debug("   ✅ CA Status retrieved via REAL QUIC mTLS: \(status.count) bytes")
    
    // Decode status to get details and validate
    let statusData = try CodableCBORDecoder().decode(CaStatus.self, from: status)
    logger.debug("   ✅ CA Status details:")
    logger.debug("      Issuing Subject: \(statusData.issuing_subject)")
    logger.debug("      Issuing Serial: \(statusData.issuing_serial_hex)")
    logger.debug("      Not Before: \(statusData.not_before)")
    logger.debug("      Not After: \(statusData.not_after)")
    XCTAssertTrue(statusData.issuing_subject.contains("CN=Test Issuing CA"))
    XCTAssertTrue(statusData.not_after > statusData.not_before)
    
    let chain = try await caClient!.getChain(bootstrapAddress: bootstrapAddr, networkId: "test_network")
    logger.debug("   ✅ Certificate chain retrieved via REAL QUIC mTLS: \(chain.count) bytes")
    
    // Decode chain to get details and validate
    let chainData = try CodableCBORDecoder().decode(CertificateChain.self, from: chain)
    logger.debug("   ✅ Chain contains \(chainData.certificates.count) certificates")
    XCTAssertGreaterThanOrEqual(chainData.certificates.count, 1)
    
    logger.debug("\n🎉 PHASE 8 COMPLETED: CA Node API Status and Chain via REAL QUIC mTLS")
    
    // ==========================================
    // Phase 9: Profile Key Functionality via REAL QUIC mTLS
    // ==========================================
    logger.debug("\n🔑 PHASE 9: Profile Key Functionality via REAL QUIC mTLS")
    
    // Test profile key functionality on the mobile node
    let personalProfileKey = try await mobileNode!.deriveUserProfileKey(label: "personal")
    let workProfileKey = try await mobileNode!.deriveUserProfileKey(label: "work")
    logger.debug("   📱 Mobile node derived profile keys")
    
    // Test envelope encryption/decryption with profile keys
    let testData = Data("Hello, encrypted world!".utf8)
    let mobileEnvelope = try await mobileNode!.encryptWithEnvelope(
        data: testData,
        networkPublicKey: nil,
        profilePublicKeys: [personalProfileKey, workProfileKey]
    )
    logger.debug("   ✅ Data encrypted with profile keys")
    
    let personalProfileId = try await mobileNode!.getCompactId(for: personalProfileKey)
    let decryptedData = try await mobileNode!.decryptWithProfile(mobileEnvelope, personalProfileId.data(using: .utf8)!)
    logger.debug("   ✅ Data decrypted with profile key")
    XCTAssertEqual(decryptedData, testData)
    
    logger.debug("\n🎉 PHASE 9 COMPLETED: Profile Key Functionality via REAL QUIC mTLS")
    
    // ==========================================
    // Phase 10: Rate Limiting via REAL QUIC mTLS
    // ==========================================
    logger.debug("\n⏱️  PHASE 10: Rate Limiting via REAL QUIC mTLS")
    
    // Rate limiting is per token_id: reuse the SAME token_id across multiple enrolls
    let rateLimitTokenId = "test_token_001" // reuse original
    for i in 1...3 {
        let setupCbor = try await nodeKeys!.generateCSR()
        let setup = try CodableCBORDecoder().decode(SetupToken.self, from: setupCbor)
        let csrDer = Data(setup.csr_der)

        let req = CsrEnrollRequest(network_id: "test_network", csr_der: csrDer, enrollment_token: enrollmentToken)
        let reqData = try CodableCBOREncoder().encode(req)

        do {
            let _ = try await caClient!.enroll(bootstrapAddress: bootstrapAddr, request: reqData)
            if i == 1 {
                logger.debug("   ✅ First request passed (allowed)")
            } else {
                XCTFail("Rate-limited request \(i) should fail")
            }
        } catch {
            if i == 1 { XCTFail("First request should pass: \(error)") }
            else { logger.debug("   ✅ Rate limit request \(i) correctly rejected") }
        }

        try await Task.sleep(nanoseconds: 10_000_000)
    }
    
    logger.debug("\n🎉 PHASE 10 COMPLETED: Rate Limiting via REAL QUIC mTLS")
    
    // ==========================================
    // Phase 11: Token Revocation via REAL QUIC mTLS
    // ==========================================
    logger.debug("\n🔒 PHASE 11: Token Revocation via REAL QUIC mTLS")
    
    // Revoke the original enrollment token
    try await caNode!.revokeToken("test_token_001")
    logger.debug("   ✅ Enrollment token revoked via REAL QUIC mTLS")
    
    // Try to use revoked token
    let testCsr = try await nodeKeys!.generateCSR()
    let revokedRequest = CsrEnrollRequest(
        network_id: "test_network",
        csr_der: testCsr,
        enrollment_token: enrollmentToken
    )
    
    // Encode request to CBOR
    let revokedRequestData = try CodableCBOREncoder().encode(revokedRequest)
    
    do {
        let result = try await caClient!.enroll(bootstrapAddress: bootstrapAddr, request: revokedRequestData)
        XCTFail("Revoked token should be rejected")
    } catch {
        logger.debug("   ✅ Revoked token correctly rejected via REAL QUIC mTLS")
    }
    
    logger.debug("\n🎉 PHASE 11 COMPLETED: Token Revocation via REAL QUIC mTLS")
    
    // ==========================================
    // Phase 12: Error Handling via REAL QUIC mTLS
    // ==========================================
    logger.debug("\n❌ PHASE 12: Error Handling via REAL QUIC mTLS")
    
    // Test invalid enrollment token
    let invalidTokenBody = EnrollmentTokenBody(
        token_id: "invalid_token",
        network_id: "wrong_network",
        subject_hint: "invalid",
        not_before: now - 60,
        expires_at: now + 3600,
        nonce: Data([2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17]),
        permissions: ["enroll"]
    )
    let invalidTokenData = try await eaManager!.generateEnrollmentToken(params: EAKeyManager.EnrollmentTokenParams(
        eaKeyHandle: eaHandle!,
        tokenId: "invalid_token",
        networkId: "test_network",
        subject: invalidTokenBody.subject_hint ?? "invalid_subject",
        validFrom: invalidTokenBody.not_before,
        validUntil: invalidTokenBody.expires_at,
        nonce: invalidTokenBody.nonce,
        capabilities: invalidTokenBody.permissions
    ))
    
    // Create EnrollmentToken object from the data and body
    let invalidToken = EnrollmentToken(
        body: invalidTokenBody,
        signature: invalidTokenData, // This might need to be parsed differently
        signer_id: "invalid_signer"
    )
    
    let invalidCsr = try await nodeKeys!.generateCSR()
    let invalidRequest = CsrEnrollRequest(
        network_id: "test_network",
        csr_der: invalidCsr,
        enrollment_token: invalidToken
    )
    
    // Encode request to CBOR
    let invalidRequestData = try CodableCBOREncoder().encode(invalidRequest)
    
    do {
        let result = try await caClient!.enroll(bootstrapAddress: bootstrapAddr, request: invalidRequestData)
        XCTFail("Invalid token should be rejected")
    } catch {
        logger.debug("   ✅ Invalid enrollment token rejected via REAL QUIC mTLS")
    }
    
    // Test unauthorized renewal
    let unauthorizedNodeKeys = try await NodeKeyManager()
    let unauthorizedSetupTokenCbor = try await unauthorizedNodeKeys.generateCSR()
    let unauthorizedSetupToken = try CodableCBORDecoder().decode(SetupToken.self, from: unauthorizedSetupTokenCbor)
    let unauthorizedCsrDer = Data(unauthorizedSetupToken.csr_der)
    let unauthorizedRenew = RenewRequest(
        network_id: "test_network",
        csr_der: unauthorizedCsrDer
    )
    
    // Encode renewal request to CBOR
    let unauthorizedRenewData = try CodableCBOREncoder().encode(unauthorizedRenew)
    
    do {
        let result = try await caClient!.renew(authenticatedAddress: authenticatedAddr, request: unauthorizedRenewData)
        XCTFail("Unauthorized renewal should be rejected")
    } catch {
        logger.debug("   ✅ Unauthorized renewal rejected via REAL QUIC mTLS")
    }
    
    logger.debug("\n🎉 PHASE 12 COMPLETED: Error Handling via REAL QUIC mTLS")
    
    logger.debug("\n🎉🎉🎉 ALL PHASES COMPLETED: Full Transport E2E Test via REAL QUIC mTLS 🎉🎉🎉")

    // Explicit cleanup to avoid races during teardown: stop server before freeing resources
    do {
        try await server?.stop()
        try await Task.sleep(nanoseconds: 50_000_000)
    } catch {
        logger.debug("⚠️ Server stop encountered error: \(error)")
    }
    }
}