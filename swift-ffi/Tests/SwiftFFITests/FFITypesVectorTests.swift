import Foundation
import SwiftCBOR
import SwiftCommon
@testable import SwiftFFI
import XCTest

final class FFITypesVectorTests: XCTestCase {
    let outputDir = URL(fileURLWithPath: "target/ffi-types-vectors-swift")

    override func setUp() {
        super.setUp()
        // Create output directory if it doesn't exist
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    }

    func testGenerateFFITypesVectors() throws {
        // Generate all FFI types test vectors
        try generateEnrollmentTokenBody()
        try generateEnrollmentToken()
        try generateSetupToken()
        try generateCsrEnrollRequest()
        try generateCsrEnrollResponse()
        try generateRenewRequest()
        try generateRenewResponse()
        try generateRevokeRequest()
        try generateRevokeResponse()
        try generateCaStatus()
        try generateChainResponse()
        try generateCrlLite()
        try generateCaErrorResponse()

        // Transport types (task11.md requirement)
        // Note: QuicTransportOptions doesn't implement Serialize in Rust, so we skip it for now
        try generatePeerInfo()
        try generateTransportRequestParams()
        try generateTransportPublishParams()
        try generateTransportCompleteRequestParams()

        print("✅ All FFI types test vectors generated successfully")
    }

    private func generateEnrollmentTokenBody() throws {
        let tokenBody = EnrollmentTokenBody(
            token_id: "test_token_001",
            network_id: "test_network",
            subject_hint: "test_subject",
            not_before: 1_757_890_822,
            expires_at: 1_757_894_422,
            nonce: Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]),
            permissions: ["enroll"]
        )

        let encoder = CodableCBOREncoder()
        let data = try encoder.encode(tokenBody)
        try data.write(to: outputDir.appendingPathComponent("enrollment_token_body_basic.bin"))
    }

    private func generateEnrollmentToken() throws {
        let tokenBody = EnrollmentTokenBody(
            token_id: "test_token_001",
            network_id: "test_network",
            subject_hint: "test_subject",
            not_before: 1_757_890_822,
            expires_at: 1_757_894_422,
            nonce: Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]),
            permissions: ["enroll"]
        )

        let enrollmentToken = EnrollmentToken(
            body: tokenBody,
            signature: Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70]),
            signer_id: "test_signer_001"
        )

        let encoder = CodableCBOREncoder()
        let data = try encoder.encode(enrollmentToken)
        try data.write(to: outputDir.appendingPathComponent("enrollment_token_basic.bin"))
    }

    private func generateSetupToken() throws {
        let setupToken = SetupToken(
            node_id: "test_node_001",
            node_public_key: Array(repeating: 1, count: 65),
            node_agreement_public_key: Array(repeating: 2, count: 65),
            csr_der: Array(repeating: 3, count: 318)
        )

        let encoder = CodableCBOREncoder()
        let data = try encoder.encode(setupToken)
        try data.write(to: outputDir.appendingPathComponent("setup_token_basic.bin"))
    }

    private func generateCsrEnrollRequest() throws {
        let tokenBody = EnrollmentTokenBody(
            token_id: "test_token_001",
            network_id: "test_network",
            subject_hint: "test_subject",
            not_before: 1_757_890_822,
            expires_at: 1_757_894_422,
            nonce: Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]),
            permissions: ["enroll"]
        )

        let enrollmentToken = EnrollmentToken(
            body: tokenBody,
            signature: Data(Array(repeating: 1, count: 70)),
            signer_id: "test_signer_001"
        )

        let csrEnrollRequest = CsrEnrollRequest(
            network_id: "test_network",
            csr_der: Data(Array(repeating: 7, count: 318)),
            enrollment_token: enrollmentToken
        )

        let encoder = CodableCBOREncoder()
        let data = try encoder.encode(csrEnrollRequest)
        try data.write(to: outputDir.appendingPathComponent("csr_enroll_request_basic.bin"))
    }

    private func generateCsrEnrollResponse() throws {
        let csrEnrollResponse = CsrEnrollResponse(
            network_id: "test_network",
            certificate_der: Array(repeating: 9, count: 1024),
            issuing_ca_der: Array(repeating: 10, count: 512),
            root_ca_der: Array(repeating: 11, count: 256),
            expires_at: 1_757_894_422
        )

        let encoder = CodableCBOREncoder()
        let data = try encoder.encode(csrEnrollResponse)
        try data.write(to: outputDir.appendingPathComponent("csr_enroll_response_basic.bin"))
    }

    private func generateRenewRequest() throws {
        let renewRequest = RenewRequest(
            network_id: "test_network",
            csr_der: Data(Array(repeating: 1, count: 318))
        )

        let encoder = CodableCBOREncoder()
        let data = try encoder.encode(renewRequest)
        try data.write(to: outputDir.appendingPathComponent("renew_request_basic.bin"))
    }

    private func generateRenewResponse() throws {
        let renewResponse = RenewResponse(
            network_id: "test_network",
            certificate_der: Array(repeating: 3, count: 1024),
            issuing_ca_der: Array(repeating: 4, count: 512),
            expires_at: 1_757_894_422
        )

        let encoder = CodableCBOREncoder()
        let data = try encoder.encode(renewResponse)
        try data.write(to: outputDir.appendingPathComponent("renew_response_basic.bin"))
    }

    private func generateRevokeRequest() throws {
        let revokeRequest = RevokeRequest(
            network_id: "test_network",
            certificate_serial: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20],
            reason: "testing"
        )

        let encoder = CodableCBOREncoder()
        let data = try encoder.encode(revokeRequest)
        try data.write(to: outputDir.appendingPathComponent("revoke_request_basic.bin"))
    }

    private func generateRevokeResponse() throws {
        let revokeResponse = RevokeResponse(
            network_id: "test_network",
            ok: true
        )

        let encoder = CodableCBOREncoder()
        let data = try encoder.encode(revokeResponse)
        try data.write(to: outputDir.appendingPathComponent("revoke_response_basic.bin"))
    }

    private func generateCaStatus() throws {
        let caStatus = CaStatus(
            network_id: "test_network",
            issuing_subject: "CN=Test Issuing CA,O=Test,C=US",
            issuing_serial_hex: "1234567890ABCDEF",
            not_before: 1_757_890_822,
            not_after: 1_757_894_422
        )

        let encoder = CodableCBOREncoder()
        let data = try encoder.encode(caStatus)
        try data.write(to: outputDir.appendingPathComponent("ca_status_basic.bin"))
    }

    private func generateChainResponse() throws {
        let chainResponse = ChainResponse(
            network_id: "test_network",
            issuing_ca_der: Array(repeating: 1, count: 512),
            root_ca_der: Array(repeating: 2, count: 256)
        )

        let encoder = CodableCBOREncoder()
        let data = try encoder.encode(chainResponse)
        try data.write(to: outputDir.appendingPathComponent("chain_response_basic.bin"))
    }

    private func generateCrlLite() throws {
        let crlLite = CrlLite(
            network_id: "test_network",
            revoked_serials: [
                [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20],
                [21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40],
            ],
            signature: Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64]),
            issuing_ca_serial_hex: "1234567890ABCDEF"
        )

        let encoder = CodableCBOREncoder()
        let data = try encoder.encode(crlLite)
        try data.write(to: outputDir.appendingPathComponent("crl_lite_basic.bin"))
    }

    private func generateCaErrorResponse() throws {
        let caErrorResponse = CaErrorResponse(
            code: "unauthorized",
            message: "Invalid enrollment token",
            reason: nil
        )

        let encoder = CodableCBOREncoder()
        let data = try encoder.encode(caErrorResponse)
        try data.write(to: outputDir.appendingPathComponent("ca_error_response_basic.bin"))
    }

    // MARK: - Transport Types Generation (task11.md requirement)

    // QuicTransportOptions doesn't implement Serialize in Rust, so we skip it for now

    private func generatePeerInfo() throws {
        let peerInfo = PeerInfo(
            publicKey: Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32]),
            addresses: ["127.0.0.1:8080", "192.168.1.100:9090"]
        )

        let encoder = CodableCBOREncoder()
        let data = try encoder.encode(peerInfo)
        try data.write(to: outputDir.appendingPathComponent("peer_info_basic.bin"))
    }

    private func generateTransportRequestParams() throws {
        let params = TransportRequestParams(
            path: "/api/test",
            correlationId: "corr_789",
            payload: Data("test payload".utf8),
            destPeerId: "peer_123",
            networkPublicKey: Data([1, 2, 3, 4, 5]),
            profilePublicKeys: [Data([6, 7, 8, 9, 10]), Data([11, 12, 13, 14, 15])]
        )

        let encoder = CodableCBOREncoder()
        let data = try encoder.encode(params)
        try data.write(to: outputDir.appendingPathComponent("transport_request_params_basic.bin"))
    }

    private func generateTransportPublishParams() throws {
        let params = TransportPublishParams(
            path: "/publish/test",
            correlationId: "pub_123",
            payload: Data("publish data".utf8),
            destPeerId: "peer_789",
            networkPublicKey: Data([1, 2, 3, 4, 5])
        )

        let encoder = CodableCBOREncoder()
        let data = try encoder.encode(params)
        try data.write(to: outputDir.appendingPathComponent("transport_publish_params_basic.bin"))
    }

    private func generateTransportCompleteRequestParams() throws {
        let params = TransportCompleteRequestParams(
            requestId: "req_456",
            responsePayload: Data("response data".utf8),
            profilePublicKeys: [Data([1, 2, 3]), Data([4, 5, 6])]
        )

        let encoder = CodableCBOREncoder()
        let data = try encoder.encode(params)
        try data.write(to: outputDir.appendingPathComponent("transport_complete_request_params_basic.bin"))
    }
}
