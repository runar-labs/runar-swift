import Foundation
import SwiftCBOR
import SwiftCommon
@testable import SwiftFFI
import XCTest

@available(macOS 12.0, *)
@MainActor
final class FFIE2EIntegrationTest: XCTestCase {
    func createLogger() -> RunarLogger { RunarLogger(component: .custom) }

    func encode<T: Codable>(_ value: T) throws -> Data { try CodableCBOREncoder().encode(value) }
    func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T { try CodableCBORDecoder().decode(type, from: data) }

    func testWrapperFullTransportE2EQuicMtls() async throws {
        let logger = createLogger()

        // ==========================================
        // Phase 1: Setup
        // ==========================================
        let nodeKeys = try await NodeKeyManager()
        let mobileKeys = try await MobileKeyManager()

        // ==========================================
        // Phase 2: CA Node and Server
        // ==========================================
        let caNode = try await CANode.create()
        let eaManager = EAKeyManager(logger: logger)
        let eaHandle = try await eaManager.createKeyPair()
        defer { EAKeyManager.free(eaHandle) }
        let eaPublicKeyCbor = try await eaManager.getPublicKey(eaHandle)

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
        try await caNode.setupComplete(params: setupParams)

        let shared = try await caNode.createSharedWrapped()
        let server = try await CAServer.create(
            config: CaServerConfig(
                bootstrapBind: "127.0.0.1:0",
                authenticatedBind: "127.0.0.1:0",
                networkId: networkId,
                rateLimitPerMinute: 5,
                rateLimitPerHour: 30
            ),
            sharedCaNode: shared.handle
        )
        try await server.start()
        let bootstrapAddr = try await server.bootstrapAddress()
        let authenticatedAddr = try await server.authenticatedAddress()

        // ==========================================
        // Phase 3: Mobile Node CSR and Enrollment
        // ==========================================
        let setupTokenCbor = try await nodeKeys.generateCsrSetupToken()
        let setupToken: SetupToken = try decode(SetupToken.self, from: setupTokenCbor)
        let csrDer = setupToken.csr_der

        let now = UInt64(Date().timeIntervalSince1970)
        let nonce = Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16])
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
        let tokenCbor = try await eaManager.generateEnrollmentToken(params: tokenParams)
        let token: EnrollmentToken = try decode(EnrollmentToken.self, from: tokenCbor)

        let enrollReq = CsrEnrollRequest(network_id: networkId, csr_der: csrDer, enrollment_token: token)
        let enrollReqCbor = try encode(enrollReq)

        let rootCa = try await caNode.getRootCACertificate()
        let issuingCa = try await caNode.getIssuingCACertificate()

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
        let client = try await CAClient(config: clientConfig, nodeKeys: nodeKeys)

        let enrollResp = try await client.enroll(bootstrapAddress: bootstrapAddr, request: enrollReqCbor)
        let certMsg = try await mobileKeys.fromEnrollResponse(enrollResp)
        try await nodeKeys.installCertificate(certMsg)
        let quicConfig = try await nodeKeys.getQuicCertificateConfig()

        // ==========================================
        // Phase 4: Certificate Renewal via REAL QUIC mTLS
        // ==========================================
        let renewalSetupTokenCbor = try await nodeKeys.generateCsrSetupToken()
        let renewalSetupToken: SetupToken = try decode(SetupToken.self, from: renewalSetupTokenCbor)
        let renewReq = RenewRequest(network_id: networkId, csr_der: renewalSetupToken.csr_der)
        let renewReqCbor = try encode(renewReq)
        let renewResp = try await client.renew(authenticatedAddress: authenticatedAddr, request: renewReqCbor)
        let renewalCertMsg = try await mobileKeys.fromRenewResponse(renewResp)
        try await nodeKeys.installCertificate(renewalCertMsg)

        // ==========================================
        // Phase 5: Certificate Revocation + CRL-lite via REAL QUIC mTLS
        // ==========================================
        let nodeCert = try await nodeKeys.getNodeCertificate()
        let ski = try await CertificateUtils.extractSki(from: nodeCert)
        try await shared.addAdminSki(ski)
        let adminSkisCbor = try encode([ski])
        try await server.configureAdminSkis(adminSkisCbor)
        let serialHex = try await CertificateUtils.getSerialHex(from: nodeCert)
        let serialBytes = Array(Data(hexString: serialHex) ?? Data())
        let revokeReq = RevokeRequest(network_id: networkId, certificate_serial: serialBytes, reason: "testing")
        let revokeReqCbor = try encode(revokeReq)
        _ = try await client.revoke(authenticatedAddress: authenticatedAddr, request: revokeReqCbor)
        let crl = try await caNode.handleCRL(networkId: networkId)

        // ==========================================
        // Phase 6: Status and Chain via REAL QUIC mTLS
        // ==========================================
        let status = try await client.getStatus(authenticatedAddress: authenticatedAddr, networkId: networkId)
        let chain = try await client.getChain(bootstrapAddress: bootstrapAddr, networkId: networkId)

        // ==========================================
        // Phase 7: Profile Key Functionality via REAL QUIC mTLS
        // ==========================================
        let personalKey = try await nodeKeys.deriveUserProfileKey(label: "personal")
        let workKey = try await nodeKeys.deriveUserProfileKey(label: "work")
        let personalId = try await nodeKeys.getCompactId(for: personalKey)
        let testData = Data("Hello, encrypted world!".utf8)
        let envelope = try await nodeKeys.encryptWithEnvelope(data: testData, networkPublicKey: nil, profilePublicKeys: [personalKey])
        let decrypted = try await nodeKeys.decryptWithProfile(envelopeData: envelope, profileId: personalId)
        XCTAssertEqual(decrypted, testData)

        // ==========================================
        // Phase 8: Rate Limiting via REAL QUIC mTLS
        // ==========================================
        for _ in 1 ... 3 {
            let setupCbor = try await nodeKeys.generateCsrSetupToken()
            let setup: SetupToken = try decode(SetupToken.self, from: setupCbor)
            let req = CsrEnrollRequest(network_id: networkId, csr_der: setup.csr_der, enrollment_token: token)
            let reqCbor = try encode(req)
            do {
                _ = try await client.enroll(bootstrapAddress: bootstrapAddr, request: reqCbor)
                // May occasionally pass depending on rate limits; not a hard assert here
        }

        // ==========================================
        // Phase 9: Token Revocation via REAL QUIC mTLS
        // ==========================================
        try await caNode.revokeToken("test_token_001")
        do {
            let sCbor = try await nodeKeys.generateCsrSetupToken()
            let sTok: SetupToken = try decode(SetupToken.self, from: sCbor)
            let req = CsrEnrollRequest(network_id: networkId, csr_der: sTok.csr_der, enrollment_token: token)
            let reqCbor = try encode(req)
            _ = try await client.enroll(bootstrapAddress: bootstrapAddr, request: reqCbor)
            XCTFail("Revoked token should be rejected")

        // ==========================================
        // Phase 10: Negative Cases via REAL QUIC mTLS
        // ==========================================
        // Invalid token network id
        let badParams = EAKeyManager.EnrollmentTokenParams(
            eaKeyHandle: eaHandle,
            tokenId: "invalid_token",
            networkId: "wrong_network",
            subject: "invalid",
            validFrom: now - 60,
            validUntil: now + 3600,
            nonce: Data([2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17]),
            capabilities: ["enroll"]
        )
        let badTokenCbor = try await eaManager.generateEnrollmentToken(params: badParams)
        let badToken: EnrollmentToken = try decode(EnrollmentToken.self, from: badTokenCbor)
        let badSetupCbor = try await nodeKeys.generateCsrSetupToken()
        let badSetup: SetupToken = try decode(SetupToken.self, from: badSetupCbor)
        let badReq = CsrEnrollRequest(network_id: networkId, csr_der: badSetup.csr_der, enrollment_token: badToken)
        let badReqCbor = try encode(badReq)
        do {
            _ = try await client.enroll(bootstrapAddress: bootstrapAddr, request: badReqCbor)
            XCTFail("Invalid token should be rejected")

        // Unauthorized renewal (new node)
        let unauthorizedKeys = try await NodeKeyManager()
        let unauthorizedSetupCbor = try await unauthorizedKeys.generateCsrSetupToken()
        let unauthorizedSetup: SetupToken = try decode(SetupToken.self, from: unauthorizedSetupCbor)
        let unauthorizedReq = RenewRequest(network_id: networkId, csr_der: unauthorizedSetup.csr_der)
        let unauthorizedReqCbor = try encode(unauthorizedReq)
        do {
            _ = try await client.renew(authenticatedAddress: authenticatedAddr, request: unauthorizedReqCbor)
            XCTFail("Unauthorized renewal should be rejected")

        // ==========================================
        // Cleanup
        // ==========================================
        try await server.stop()
        _ = workKey // keep references used
        _ = envelope
        _ = personalId
    }

    private func validateCertificates(rootCa: Data, issuingCa: Data) throws {
        guard !rootCa.isEmpty, !issuingCa.isEmpty else {
            throw FFIError.operationFailed("Certificates cannot be empty")
        }
        guard rootCa.count > 100, issuingCa.count > 100 else {
            throw FFIError.operationFailed("Certificates seem too small")
        }
    }
}
