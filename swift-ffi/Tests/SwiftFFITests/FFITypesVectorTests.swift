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
        
        print("✅ All FFI types test vectors generated successfully")
    }
    
    private func generateEnrollmentTokenBody() throws {
        let tokenBody = EnrollmentTokenBody(
            token_id: "test_token_001",
            network_id: "test_network",
            subject_hint: "test_subject",
            not_before: 1234567890,
            expires_at: 1234567890 + 3600,
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
            not_before: 1234567890,
            expires_at: 1234567890 + 3600,
            nonce: Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]),
            permissions: ["enroll"]
        )
        
        let enrollmentToken = EnrollmentToken(
            body: tokenBody,
            signature: Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64]),
            signer_id: "test_signer_id"
        )
        
        let encoder = CodableCBOREncoder()
        let data = try encoder.encode(enrollmentToken)
        try data.write(to: outputDir.appendingPathComponent("enrollment_token_basic.bin"))
    }
    
    private func generateSetupToken() throws {
        let setupToken = SetupToken(
            node_id: "test_compact_id",
            node_public_key: Array(1...65).map { UInt8($0 % 256) },
            node_agreement_public_key: Array(2...67).map { UInt8($0 % 256) },
            csr_der: Array(3...320).map { UInt8($0 % 256) }
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
            not_before: 1234567890,
            expires_at: 1234567890 + 3600,
            nonce: Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]),
            permissions: ["enroll"]
        )
        
        let enrollmentToken = EnrollmentToken(
            body: tokenBody,
            signature: Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64]),
            signer_id: "test_signer_id"
        )
        
        let csrEnrollRequest = CsrEnrollRequest(
            network_id: "test_network",
            csr_der: Data(Array(1...100).map { UInt8($0 % 256) }),
            enrollment_token: enrollmentToken
        )
        
        let encoder = CodableCBOREncoder()
        let data = try encoder.encode(csrEnrollRequest)
        try data.write(to: outputDir.appendingPathComponent("csr_enroll_request_basic.bin"))
    }
    
    private func generateCsrEnrollResponse() throws {
        let csrEnrollResponse = CsrEnrollResponse(
            network_id: "test_network",
            certificate_der: Array(1...200).map { UInt8($0 % 256) },
            issuing_ca_der: Array(1...200).map { UInt8($0 % 256) },
            root_ca_der: Array(1...200).map { UInt8($0 % 256) },
            expires_at: 1234567890 + 86400
        )
        
        let encoder = CodableCBOREncoder()
        let data = try encoder.encode(csrEnrollResponse)
        try data.write(to: outputDir.appendingPathComponent("csr_enroll_response_basic.bin"))
    }
    
    private func generateRenewRequest() throws {
        let renewRequest = RenewRequest(
            network_id: "test_network",
            csr_der: Data(Array(1...100).map { UInt8($0 % 256) })
        )
        
        let encoder = CodableCBOREncoder()
        let data = try encoder.encode(renewRequest)
        try data.write(to: outputDir.appendingPathComponent("renew_request_basic.bin"))
    }
    
    private func generateRenewResponse() throws {
        let renewResponse = RenewResponse(
            network_id: "test_network",
            certificate_der: Array(1...200).map { UInt8($0 % 256) },
            issuing_ca_der: Array(1...200).map { UInt8($0 % 256) },
            expires_at: 1234567890 + 86400
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
            not_before: 1234567890,
            not_after: 1234567890 + 31536000 // 1 year
        )
        
        let encoder = CodableCBOREncoder()
        let data = try encoder.encode(caStatus)
        try data.write(to: outputDir.appendingPathComponent("ca_status_basic.bin"))
    }
    
    private func generateChainResponse() throws {
        let chainResponse = ChainResponse(
            network_id: "test_network",
            issuing_ca_der: Array(1...200).map { UInt8($0 % 256) },
            root_ca_der: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200]
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
                [21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40]
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
            code: "INVALID_TOKEN",
            message: "The provided enrollment token is invalid or expired",
            reason: "token_expired"
        )
        
        let encoder = CodableCBOREncoder()
        let data = try encoder.encode(caErrorResponse)
        try data.write(to: outputDir.appendingPathComponent("ca_error_response_basic.bin"))
    }
}
