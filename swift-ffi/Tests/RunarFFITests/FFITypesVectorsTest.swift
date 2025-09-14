import Foundation
import XCTest
import SwiftCBOR
import RunarFFI

/// FFI Types CBOR Test Vectors Generator
/// Generates test vectors for all FFI types used in enrollment process
@available(macOS 11.0, *)
final class FFITypesVectorsTest: XCTestCase {
    
    // MARK: - Data Structures (matching Rust exactly)
    
    /// EnrollmentTokenBody structure matching Rust implementation exactly
    struct EnrollmentTokenBody: Codable {
        let token_id: String
        let network_id: String
        let subject_hint: String?
        let not_before: UInt64
        let expires_at: UInt64
        let nonce: [UInt8] // Rust uses [u8; 16], Swift uses [UInt8]
        let permissions: [String]
        
        enum CodingKeys: String, CodingKey {
            case token_id
            case network_id
            case subject_hint
            case not_before
            case expires_at
            case nonce
            case permissions
        }
    }
    
    /// EnrollmentToken structure matching Rust implementation exactly
    struct EnrollmentToken: Codable {
        let body: EnrollmentTokenBody
        let signature: [UInt8] // Rust uses Vec<u8>, Swift uses [UInt8]
        let signer_id: String
        
        enum CodingKeys: String, CodingKey {
            case body
            case signature
            case signer_id
        }
    }
    
    /// SetupToken structure matching Rust implementation exactly
    struct SetupToken: Codable {
        let node_public_key: [UInt8] // Rust uses Vec<u8>, Swift uses [UInt8]
        let node_agreement_public_key: [UInt8] // Rust uses Vec<u8>, Swift uses [UInt8]
        let csr_der: [UInt8] // Rust uses Vec<u8>, Swift uses [UInt8]
        let node_id: String
        
        enum CodingKeys: String, CodingKey {
            case node_public_key
            case node_agreement_public_key
            case csr_der
            case node_id
        }
    }
    
    /// CsrEnrollRequest structure matching Rust implementation exactly
    struct CsrEnrollRequest: Codable {
        let network_id: String
        let csr_der: [UInt8] // Rust uses Vec<u8>, Swift uses [UInt8]
        let enrollment_token: EnrollmentToken
    }
    
    /// CsrEnrollResponse structure matching Rust implementation exactly
    struct CsrEnrollResponse: Codable {
        let network_id: String
        let certificate_der: [UInt8] // Rust uses Vec<u8>, Swift uses [UInt8]
        let issuing_ca_der: [UInt8] // Rust uses Vec<u8>, Swift uses [UInt8]
        let root_ca_der: [UInt8]? // Rust uses Option<Vec<u8>>, Swift uses [UInt8]?
        let expires_at: UInt64
    }
    
    /// CaErrorResponse structure matching Rust implementation exactly
    struct CaErrorResponse: Codable {
        let code: String
        let message: String
        let reason: String?
        
        init(code: String, message: String, reason: String? = nil) {
            self.code = code
            self.message = message
            self.reason = reason
        }
    }
    
    // MARK: - Test Vectors Generation
    
    func testGenerateFFITypesVectors() throws {
        print("🔬 Generating FFI Types CBOR Test Vectors")
        print("=========================================")
        
        // Create output directory
        let outputDir = URL(fileURLWithPath: "target/ffi-types-vectors-swift")
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        
        // Generate all test vectors
        try generateEnrollmentTokenBodyVectors(outputDir: outputDir)
        try generateEnrollmentTokenVectors(outputDir: outputDir)
        try generateSetupTokenVectors(outputDir: outputDir)
        try generateCsrEnrollRequestVectors(outputDir: outputDir)
        try generateCsrEnrollResponseVectors(outputDir: outputDir)
        try generateCaErrorResponseVectors(outputDir: outputDir)
        
        print("✅ Generated FFI types vectors to \(outputDir.path)")
    }
    
    // MARK: - EnrollmentTokenBody Vectors
    
    private func generateEnrollmentTokenBodyVectors(outputDir: URL) throws {
        print("🔍 Generating EnrollmentTokenBody vectors...")
        
        // Basic enrollment token body
        let basicBody = EnrollmentTokenBody(
            token_id: "test_token_001",
            network_id: "test_network",
            subject_hint: "test_subject",
            not_before: 1757890822,
            expires_at: 1757894422,
            nonce: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
            permissions: ["enroll"]
        )
        
        try writeCborVector(outputDir: outputDir, filename: "enrollment_token_body_basic.bin", data: basicBody)
        
        // Enrollment token body with multiple permissions
        let multiPermissionsBody = EnrollmentTokenBody(
            token_id: "test_token_002",
            network_id: "test_network",
            subject_hint: "test_subject_2",
            not_before: 1757890822,
            expires_at: 1757894422,
            nonce: [16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1],
            permissions: ["enroll", "renew"]
        )
        
        try writeCborVector(outputDir: outputDir, filename: "enrollment_token_body_multi_permissions.bin", data: multiPermissionsBody)
        
        // Enrollment token body without subject hint
        let noSubjectBody = EnrollmentTokenBody(
            token_id: "test_token_003",
            network_id: "test_network",
            subject_hint: nil,
            not_before: 1757890822,
            expires_at: 1757894422,
            nonce: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
            permissions: ["enroll"]
        )
        
        try writeCborVector(outputDir: outputDir, filename: "enrollment_token_body_no_subject.bin", data: noSubjectBody)
        
        print("✅ EnrollmentTokenBody vectors generated")
    }
    
    // MARK: - EnrollmentToken Vectors
    
    private func generateEnrollmentTokenVectors(outputDir: URL) throws {
        print("🔍 Generating EnrollmentToken vectors...")
        
        // Basic enrollment token
        let basicBody = EnrollmentTokenBody(
            token_id: "test_token_001",
            network_id: "test_network",
            subject_hint: "test_subject",
            not_before: 1757890822,
            expires_at: 1757894422,
            nonce: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
            permissions: ["enroll"]
        )
        
        let basicToken = EnrollmentToken(
            body: basicBody,
            signature: Array(1...70), // 70-byte signature
            signer_id: "test_signer_001"
        )
        
        try writeCborVector(outputDir: outputDir, filename: "enrollment_token_basic.bin", data: basicToken)
        
        // Enrollment token with longer signature
        let longSignatureBody = EnrollmentTokenBody(
            token_id: "test_token_002",
            network_id: "test_network",
            subject_hint: "test_subject_2",
            not_before: 1757890822,
            expires_at: 1757894422,
            nonce: [16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1],
            permissions: ["enroll", "renew"]
        )
        
        let longSignatureToken = EnrollmentToken(
            body: longSignatureBody,
            signature: Array(repeating: 255, count: 128), // 128-byte signature
            signer_id: "test_signer_002"
        )
        
        try writeCborVector(outputDir: outputDir, filename: "enrollment_token_long_signature.bin", data: longSignatureToken)
        
        print("✅ EnrollmentToken vectors generated")
    }
    
    // MARK: - SetupToken Vectors
    
    private func generateSetupTokenVectors(outputDir: URL) throws {
        print("🔍 Generating SetupToken vectors...")
        
        // Basic setup token
        let basicSetup = SetupToken(
            node_public_key: Array(repeating: 1, count: 65), // 65-byte public key
            node_agreement_public_key: Array(repeating: 2, count: 65), // 65-byte agreement key
            csr_der: Array(repeating: 3, count: 318), // 318-byte CSR (typical size)
            node_id: "test_node_001"
        )
        
        try writeCborVector(outputDir: outputDir, filename: "setup_token_basic.bin", data: basicSetup)
        
        // Setup token with different key sizes
        let differentSizesSetup = SetupToken(
            node_public_key: Array(repeating: 4, count: 33), // 33-byte compressed key
            node_agreement_public_key: Array(repeating: 5, count: 32), // 32-byte key
            csr_der: Array(repeating: 6, count: 256), // 256-byte CSR
            node_id: "test_node_002"
        )
        
        try writeCborVector(outputDir: outputDir, filename: "setup_token_different_sizes.bin", data: differentSizesSetup)
        
        print("✅ SetupToken vectors generated")
    }
    
    // MARK: - CsrEnrollRequest Vectors
    
    private func generateCsrEnrollRequestVectors(outputDir: URL) throws {
        print("🔍 Generating CsrEnrollRequest vectors...")
        
        // Create enrollment token for the request
        let tokenBody = EnrollmentTokenBody(
            token_id: "test_token_001",
            network_id: "test_network",
            subject_hint: "test_subject",
            not_before: 1757890822,
            expires_at: 1757894422,
            nonce: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
            permissions: ["enroll"]
        )
        
        let enrollmentToken = EnrollmentToken(
            body: tokenBody,
            signature: Array(repeating: 1, count: 70), // 70-byte signature (all ones)
            signer_id: "test_signer_001"
        )
        
        // Basic CSR enroll request
        let basicRequest = CsrEnrollRequest(
            network_id: "test_network",
            csr_der: Array(repeating: 7, count: 318), // 318-byte CSR
            enrollment_token: enrollmentToken
        )
        
        try writeCborVector(outputDir: outputDir, filename: "csr_enroll_request_basic.bin", data: basicRequest)
        
        // CSR enroll request with different CSR size
        let differentCsrRequest = CsrEnrollRequest(
            network_id: "test_network",
            csr_der: Array(repeating: 8, count: 256), // 256-byte CSR
            enrollment_token: enrollmentToken
        )
        
        try writeCborVector(outputDir: outputDir, filename: "csr_enroll_request_different_csr.bin", data: differentCsrRequest)
        
        print("✅ CsrEnrollRequest vectors generated")
    }
    
    // MARK: - CsrEnrollResponse Vectors
    
    private func generateCsrEnrollResponseVectors(outputDir: URL) throws {
        print("🔍 Generating CsrEnrollResponse vectors...")
        
        // Basic CSR enroll response
        let basicResponse = CsrEnrollResponse(
            network_id: "test_network",
            certificate_der: Array(repeating: 9, count: 1024), // 1KB certificate
            issuing_ca_der: Array(repeating: 10, count: 512), // Intermediate cert
            root_ca_der: Array(repeating: 11, count: 256), // Root cert
            expires_at: 1757894422
        )
        
        try writeCborVector(outputDir: outputDir, filename: "csr_enroll_response_basic.bin", data: basicResponse)
        
        // CSR enroll response without root CA
        let noRootResponse = CsrEnrollResponse(
            network_id: "test_network",
            certificate_der: Array(repeating: 12, count: 2048), // 2KB certificate
            issuing_ca_der: Array(repeating: 13, count: 1024), // Intermediate cert
            root_ca_der: nil, // No root cert
            expires_at: 1757894422
        )
        
        try writeCborVector(outputDir: outputDir, filename: "csr_enroll_response_no_root.bin", data: noRootResponse)
        
        print("✅ CsrEnrollResponse vectors generated")
    }
    
    // MARK: - CaErrorResponse Vectors
    
    private func generateCaErrorResponseVectors(outputDir: URL) throws {
        print("🔍 Generating CaErrorResponse vectors...")
        
        // Basic error response
        let basicError = CaErrorResponse(
            code: "unauthorized",
            message: "Invalid enrollment token"
        )
        try writeCborVector(outputDir: outputDir, filename: "ca_error_response_basic.bin", data: basicError)
        
        // Error response with reason
        let errorWithReason = CaErrorResponse(
            code: "forbidden",
            message: "CSR CN mismatch",
            reason: "csr_cn_mismatch"
        )
        try writeCborVector(outputDir: outputDir, filename: "ca_error_response_with_reason.bin", data: errorWithReason)
        
        // Rate limited error
        let rateLimitedError = CaErrorResponse(
            code: "rate_limited",
            message: "Too many requests",
            reason: "rate_limit_exceeded"
        )
        try writeCborVector(outputDir: outputDir, filename: "ca_error_response_rate_limited.bin", data: rateLimitedError)
        
        print("✅ CaErrorResponse vectors generated")
    }
    
    // MARK: - Helper Functions
    
    private func writeCborVector<T: Codable>(outputDir: URL, filename: String, data: T) throws {
        let cborData = try CodableCBOREncoder().encode(data)
        let fileURL = outputDir.appendingPathComponent(filename)
        try cborData.write(to: fileURL)
        print("   📝 \(filename): \(cborData.count) bytes")
    }
}
