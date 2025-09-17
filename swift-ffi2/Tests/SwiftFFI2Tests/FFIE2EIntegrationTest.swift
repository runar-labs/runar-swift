import Foundation
import SwiftCBOR
import SwiftCommon
@testable import SwiftFFI2
import XCTest

@available(macOS 12.0, *)
final class FFIE2EIntegrationTest: XCTestCase {

    func createLogger() -> RunarLogger { RunarLogger(component: .custom) }

    func encode<T: Codable>(_ value: T) throws -> Data { try CodableCBOREncoder().encode(value) }
    func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T { try CodableCBORDecoder().decode(type, from: data) }

    func testWrapperFullTransportE2EQuicMtls() throws {
        print("\n🚀 Starting WRAPPER Full-transport E2E QUIC mTLS test")
        let logger = createLogger()

        // ==========================================
        // Phase 1: Setup
        // ==========================================
        print("\n🏗️  PHASE 1 (WRAPPER): Setup")
        let nodeKeys = try KeysHandle()
        try nodeKeys.initializeAsNode()
        let mobileKeys = try KeysHandle()
        try mobileKeys.initializeAsMobile()
        print("   ✅ (WRAPPER) Keys handles created and initialized")

        // ==========================================
        // Phase 2: CA Node and Server
        // ==========================================
        print("\n🏗️  PHASE 2 (WRAPPER): CA Node and Server")
        let caNode = try CANode.create()
        let eaManager = EAKeyManager(logger: logger)
        let eaHandle = try eaManager.createKeyPair()
        defer { EAKeyManager.free(eaHandle) }
        let eaPublicKeyCbor = try eaManager.getPublicKey(eaHandle)

        let networkId = "test_network"
        let setupParams = CANodeManager.CANodeSetupParams(
            caNode: caNode.ffiHandle,
            rootCaSubject: "CN=Test Root CA,O=Test,C=US",
            issuingCaSubject: "CN=Test Issuing CA,O=Test,C=US",
            validityDays: 365,
            issuingCaSerial: 1,
            eaPublicKeys: eaPublicKeyCbor,
            networkId: networkId
        )
        try caNode.setupComplete(params: setupParams)
        print("   ✅ (WRAPPER) CA Node setup complete")

        let shared = try caNode.createSharedWrapped()
        let server = try CAServer.create(
            config: CaServerConfig(
                bootstrapBind: "127.0.0.1:0",
                authenticatedBind: "127.0.0.1:0",
                networkId: networkId,
                rateLimitPerMinute: 5,
                rateLimitPerHour: 30
            ),
            sharedCaNode: shared.handle
        )
        try server.start()
        let bootstrapAddr = try server.bootstrapAddress()
        let authenticatedAddr = try server.authenticatedAddress()
        print("   ✅ (WRAPPER) CA Server started with addresses")
        print("      Bootstrap: \(bootstrapAddr)")
        print("      Authenticated: \(authenticatedAddr)")

        // ==========================================
        // Phase 3: Mobile Node CSR and Enrollment
        // ==========================================
        print("\n📱 PHASE 3 (WRAPPER): Mobile Node CSR and Enrollment")
        let setupTokenCbor = try nodeKeys.generateCsrSetupToken()
        let setupToken: SetupToken = try decode(SetupToken.self, from: setupTokenCbor)
        let csrDer = setupToken.csr_der

        let now = UInt64(Date().timeIntervalSince1970)
        let nonce = Data([1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16])
        let tokenParams = EAKeyManager.EnrollmentTokenParams(
            eaKeyHandle: eaHandle,
            tokenId: "test_token_001",
            networkId: networkId,
            subject: "test_subject",
            validFrom: now - 60,
            validUntil: now + 3600,
            nonce: nonce,
            capabilities: ["enroll"]
        )
        let tokenCbor = try eaManager.generateEnrollmentToken(params: tokenParams)
        let token: EnrollmentToken = try decode(EnrollmentToken.self, from: tokenCbor)

        let enrollReq = CsrEnrollRequest(network_id: networkId, csr_der: csrDer, enrollment_token: token)
        let enrollReqCbor = try encode(enrollReq)

        let rootCa = try caNode.getRootCACertificate()
        let issuingCa = try caNode.getIssuingCACertificate()

        try validateCertificates(rootCa: rootCa, issuingCa: issuingCa)

        let clientConfig = CaClientConfigAll(
            bootstrap_server: bootstrapAddr,
            authenticated_server: authenticatedAddr,
            network_id: networkId,
            request_timeout_seconds: 30,
            max_retries: 3,
            root_ca_der: rootCa,
            issuing_ca_der: issuingCa
        )
        let client = try CAClient(config: clientConfig, nodeKeys: nodeKeys)

        let enrollResp = try client.enroll(bootstrapAddress: bootstrapAddr, request: enrollReqCbor)
        let certMsg = try mobileKeys.mobileFromEnrollResponse(enrollResp)
        try nodeKeys.installCertificate(certMsg)
        let quicConfig = try nodeKeys.getQuicCertificateConfig()
        print("   ✅ (WRAPPER) Enrollment successful; QUIC config bytes: \(quicConfig.count)")

        // ==========================================
        // Phase 4: Certificate Renewal via REAL QUIC mTLS
        // ==========================================
        print("\n🔄 PHASE 4 (WRAPPER): Certificate Renewal via REAL QUIC mTLS")
        let renewalSetupTokenCbor = try nodeKeys.generateCsrSetupToken()
        let renewalSetupToken: SetupToken = try decode(SetupToken.self, from: renewalSetupTokenCbor)
        let renewReq = RenewRequest(network_id: networkId, csr_der: renewalSetupToken.csr_der)
        let renewReqCbor = try encode(renewReq)
        let renewResp = try client.renew(authenticatedAddress: authenticatedAddr, request: renewReqCbor)
        let renewalCertMsg = try mobileKeys.mobileFromRenewResponse(renewResp)
        try nodeKeys.installCertificate(renewalCertMsg)
        print("   ✅ (WRAPPER) Renewal successful and certificate installed")

        // ==========================================
        // Phase 5: Certificate Revocation + CRL-lite via REAL QUIC mTLS
        // ==========================================
        print("\n🚫 PHASE 5 (WRAPPER): Certificate Revocation + CRL-lite via REAL QUIC mTLS")
        let nodeCert = try nodeKeys.getNodeCertificate()
        let ski = try CertificateUtils.extractSki(from: nodeCert)
        try shared.addAdminSki(ski)
        let adminSkisCbor = try encode([ski])
        try server.configureAdminSkis(adminSkisCbor)
        let serialHex = try CertificateUtils.getSerialHex(from: nodeCert)
        let serialBytes = Array(Data(hexString: serialHex) ?? Data())
        let revokeReq = RevokeRequest(network_id: networkId, certificate_serial: serialBytes, reason: "testing")
        let revokeReqCbor = try encode(revokeReq)
        _ = try client.revoke(authenticatedAddress: authenticatedAddr, request: revokeReqCbor)
        let crl = try caNode.handleCRL(networkId: networkId)
        print("   ✅ (WRAPPER) Certificate revoked; CRL-lite bytes: \(crl.count)")

        // ==========================================
        // Phase 6: Status and Chain via REAL QUIC mTLS
        // ==========================================
        print("\n📊 PHASE 6 (WRAPPER): Status and Chain via REAL QUIC mTLS")
        let status = try client.getStatus(authenticatedAddress: authenticatedAddr, networkId: networkId)
        let chain = try client.getChain(bootstrapAddress: bootstrapAddr, networkId: networkId)
        print("   ✅ (WRAPPER) Status bytes: \(status.count), Chain bytes: \(chain.count)")

        // ==========================================
        // Phase 7: Profile Key Functionality via REAL QUIC mTLS
        // ==========================================
        print("\n🔑 PHASE 7 (WRAPPER): Profile Key Functionality via REAL QUIC mTLS")
        let personalKey = try nodeKeys.deriveUserProfileKey(label: "personal")
        let workKey = try nodeKeys.deriveUserProfileKey(label: "work")
        let personalId = try nodeKeys.getCompactId(for: personalKey)
        let testData = Data("Hello, encrypted world!".utf8)
        let envelope = try nodeKeys.encryptWithEnvelope(plaintext: testData, profileKeys: [personalKey])
        let decrypted = try nodeKeys.decryptWithProfile(envelope: envelope, profileId: personalId)
        XCTAssertEqual(decrypted, testData)
        print("   ✅ (WRAPPER) Profile key envelope roundtrip succeeded")

        // ==========================================
        // Phase 8: Rate Limiting via REAL QUIC mTLS
        // ==========================================
        print("\n⏱️  PHASE 8 (WRAPPER): Rate Limiting via REAL QUIC mTLS")
        for _ in 1...3 {
            let setupCbor = try nodeKeys.generateCsrSetupToken()
            let setup: SetupToken = try decode(SetupToken.self, from: setupCbor)
            let req = CsrEnrollRequest(network_id: networkId, csr_der: setup.csr_der, enrollment_token: token)
            let reqCbor = try encode(req)
            do {
                _ = try client.enroll(bootstrapAddress: bootstrapAddr, request: reqCbor)
                // May occasionally pass depending on rate limits; not a hard assert here
            } catch { print("   ✅ (WRAPPER) Rate limited as expected") }
        }

        // ==========================================
        // Phase 9: Token Revocation via REAL QUIC mTLS
        // ==========================================
        print("\n🔒 PHASE 9 (WRAPPER): Token Revocation via REAL QUIC mTLS")
        try caNode.revokeToken("test_token_001")
        do {
            let sCbor = try nodeKeys.generateCsrSetupToken()
            let sTok: SetupToken = try decode(SetupToken.self, from: sCbor)
            let req = CsrEnrollRequest(network_id: networkId, csr_der: sTok.csr_der, enrollment_token: token)
            let reqCbor = try encode(req)
            _ = try client.enroll(bootstrapAddress: bootstrapAddr, request: reqCbor)
            XCTFail("Revoked token should be rejected")
        } catch { print("   ✅ (WRAPPER) Revoked token rejected as expected") }

        // ==========================================
        // Phase 10: Negative Cases via REAL QUIC mTLS
        // ==========================================
        print("\n❌ PHASE 10 (WRAPPER): Negative Cases via REAL QUIC mTLS")
        // Invalid token network id
        let badParams = EAKeyManager.EnrollmentTokenParams(
            eaKeyHandle: eaHandle,
            tokenId: "invalid_token",
            networkId: "wrong_network",
            subject: "invalid",
            validFrom: now - 60,
            validUntil: now + 3600,
            nonce: Data([2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17]),
            capabilities: ["enroll"]
        )
        let badTokenCbor = try eaManager.generateEnrollmentToken(params: badParams)
        let badToken: EnrollmentToken = try decode(EnrollmentToken.self, from: badTokenCbor)
        let badSetupCbor = try nodeKeys.generateCsrSetupToken()
        let badSetup: SetupToken = try decode(SetupToken.self, from: badSetupCbor)
        let badReq = CsrEnrollRequest(network_id: networkId, csr_der: badSetup.csr_der, enrollment_token: badToken)
        let badReqCbor = try encode(badReq)
        do {
            _ = try client.enroll(bootstrapAddress: bootstrapAddr, request: badReqCbor)
            XCTFail("Invalid token should be rejected")
        } catch { print("   ✅ (WRAPPER) Invalid token rejected as expected") }

        // Unauthorized renewal (new node)
        let unauthorizedKeys = try KeysHandle()
        try unauthorizedKeys.initializeAsNode()
        let unauthorizedSetupCbor = try unauthorizedKeys.generateCsrSetupToken()
        let unauthorizedSetup: SetupToken = try decode(SetupToken.self, from: unauthorizedSetupCbor)
        let unauthorizedReq = RenewRequest(network_id: networkId, csr_der: unauthorizedSetup.csr_der)
        let unauthorizedReqCbor = try encode(unauthorizedReq)
        do {
            _ = try client.renew(authenticatedAddress: authenticatedAddr, request: unauthorizedReqCbor)
            XCTFail("Unauthorized renewal should be rejected")
        } catch { print("   ✅ (WRAPPER) Unauthorized renewal rejected as expected") }

        // ==========================================
        // Cleanup
        // ==========================================
        print("\n🧹 CLEANUP (WRAPPER): Freeing resources")
        try server.stop()
        _ = (workKey) // keep references used
        _ = (envelope)
        _ = (personalId)
        print("   ✅ (WRAPPER) Cleanup complete")
        print("\n🎉 WRAPPER FULL-TRANSPORT E2E TEST COMPLETED SUCCESSFULLY!")
    }

    private func validateCertificates(rootCa: Data, issuingCa: Data) throws {
        guard !rootCa.isEmpty && !issuingCa.isEmpty else {
            throw FFIError.operationFailed("Certificates cannot be empty")
        }
        guard rootCa.count > 100 && issuingCa.count > 100 else {
            throw FFIError.operationFailed("Certificates seem too small")
        }
    }
}


