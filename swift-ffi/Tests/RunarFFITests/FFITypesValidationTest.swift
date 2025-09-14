import Foundation
import XCTest
import SwiftCBOR
import RunarFFI

/// FFI Types CBOR Cross-Platform Validation Test
/// Validates that Swift and Rust CBOR serialization/deserialization are compatible
@available(macOS 11.0, *)
final class FFITypesValidationTest: XCTestCase {
    
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
    
    // MARK: - Validation Tests
    
    func testValidateEnrollmentTokenBody() throws {
        print("🔍 Validating EnrollmentTokenBody...")
        
        let swiftData = try readBytes(filename: "enrollment_token_body_basic.bin")
        let rustData = try readBytes(filename: "enrollment_token_body_basic.bin", isRust: true)
        
        let swiftBody = try CodableCBORDecoder().decode(EnrollmentTokenBody.self, from: swiftData)
        let rustBody = try CodableCBORDecoder().decode(EnrollmentTokenBody.self, from: rustData)
        
        XCTAssertEqual(swiftBody.token_id, rustBody.token_id, "token_id mismatch")
        XCTAssertEqual(swiftBody.network_id, rustBody.network_id, "network_id mismatch")
        XCTAssertEqual(swiftBody.subject_hint, rustBody.subject_hint, "subject_hint mismatch")
        XCTAssertEqual(swiftBody.not_before, rustBody.not_before, "not_before mismatch")
        XCTAssertEqual(swiftBody.expires_at, rustBody.expires_at, "expires_at mismatch")
        XCTAssertEqual(swiftBody.nonce, rustBody.nonce, "nonce mismatch")
        XCTAssertEqual(swiftBody.permissions, rustBody.permissions, "permissions mismatch")
        
        print("✅ EnrollmentTokenBody validation passed")
    }
    
    func testValidateEnrollmentToken() throws {
        print("🔍 Validating EnrollmentToken...")
        
        let swiftData = try readBytes(filename: "enrollment_token_basic.bin")
        let rustData = try readBytes(filename: "enrollment_token_basic.bin", isRust: true)
        
        let swiftToken = try CodableCBORDecoder().decode(EnrollmentToken.self, from: swiftData)
        let rustToken = try CodableCBORDecoder().decode(EnrollmentToken.self, from: rustData)
        
        // Validate body
        XCTAssertEqual(swiftToken.body.token_id, rustToken.body.token_id, "body.token_id mismatch")
        XCTAssertEqual(swiftToken.body.network_id, rustToken.body.network_id, "body.network_id mismatch")
        XCTAssertEqual(swiftToken.body.subject_hint, rustToken.body.subject_hint, "body.subject_hint mismatch")
        XCTAssertEqual(swiftToken.body.not_before, rustToken.body.not_before, "body.not_before mismatch")
        XCTAssertEqual(swiftToken.body.expires_at, rustToken.body.expires_at, "body.expires_at mismatch")
        XCTAssertEqual(swiftToken.body.nonce, rustToken.body.nonce, "body.nonce mismatch")
        XCTAssertEqual(swiftToken.body.permissions, rustToken.body.permissions, "body.permissions mismatch")
        
        // Validate signature and signer_id
        XCTAssertEqual(swiftToken.signature, rustToken.signature, "signature mismatch")
        XCTAssertEqual(swiftToken.signer_id, rustToken.signer_id, "signer_id mismatch")
        
        print("✅ EnrollmentToken validation passed")
    }
    
    func testValidateSetupToken() throws {
        print("🔍 Validating SetupToken...")
        
        let swiftData = try readBytes(filename: "setup_token_basic.bin")
        let rustData = try readBytes(filename: "setup_token_basic.bin", isRust: true)
        
        let swiftSetup = try CodableCBORDecoder().decode(SetupToken.self, from: swiftData)
        let rustSetup = try CodableCBORDecoder().decode(SetupToken.self, from: rustData)
        
        XCTAssertEqual(swiftSetup.node_public_key, rustSetup.node_public_key, "node_public_key mismatch")
        XCTAssertEqual(swiftSetup.node_agreement_public_key, rustSetup.node_agreement_public_key, "node_agreement_public_key mismatch")
        XCTAssertEqual(swiftSetup.csr_der, rustSetup.csr_der, "csr_der mismatch")
        XCTAssertEqual(swiftSetup.node_id, rustSetup.node_id, "node_id mismatch")
        
        print("✅ SetupToken validation passed")
    }
    
    func testValidateCsrEnrollRequest() throws {
        print("🔍 Validating CsrEnrollRequest...")
        
        let swiftData = try readBytes(filename: "csr_enroll_request_basic.bin")
        let rustData = try readBytes(filename: "csr_enroll_request_basic.bin", isRust: true)
        
        let swiftRequest = try CodableCBORDecoder().decode(CsrEnrollRequest.self, from: swiftData)
        let rustRequest = try CodableCBORDecoder().decode(CsrEnrollRequest.self, from: rustData)
        
        XCTAssertEqual(swiftRequest.network_id, rustRequest.network_id, "network_id mismatch")
        XCTAssertEqual(swiftRequest.csr_der, rustRequest.csr_der, "csr_der mismatch")
        
        // Validate enrollment token
        XCTAssertEqual(swiftRequest.enrollment_token.body.token_id, rustRequest.enrollment_token.body.token_id, "enrollment_token.body.token_id mismatch")
        XCTAssertEqual(swiftRequest.enrollment_token.body.network_id, rustRequest.enrollment_token.body.network_id, "enrollment_token.body.network_id mismatch")
        XCTAssertEqual(swiftRequest.enrollment_token.body.subject_hint, rustRequest.enrollment_token.body.subject_hint, "enrollment_token.body.subject_hint mismatch")
        XCTAssertEqual(swiftRequest.enrollment_token.body.not_before, rustRequest.enrollment_token.body.not_before, "enrollment_token.body.not_before mismatch")
        XCTAssertEqual(swiftRequest.enrollment_token.body.expires_at, rustRequest.enrollment_token.body.expires_at, "enrollment_token.body.expires_at mismatch")
        XCTAssertEqual(swiftRequest.enrollment_token.body.nonce, rustRequest.enrollment_token.body.nonce, "enrollment_token.body.nonce mismatch")
        XCTAssertEqual(swiftRequest.enrollment_token.body.permissions, rustRequest.enrollment_token.body.permissions, "enrollment_token.body.permissions mismatch")
        XCTAssertEqual(swiftRequest.enrollment_token.signature, rustRequest.enrollment_token.signature, "enrollment_token.signature mismatch")
        XCTAssertEqual(swiftRequest.enrollment_token.signer_id, rustRequest.enrollment_token.signer_id, "enrollment_token.signer_id mismatch")
        
        print("✅ CsrEnrollRequest validation passed")
    }
    
    func testValidateCsrEnrollResponse() throws {
        print("🔍 Validating CsrEnrollResponse...")
        
        let swiftData = try readBytes(filename: "csr_enroll_response_basic.bin")
        let rustData = try readBytes(filename: "csr_enroll_response_basic.bin", isRust: true)
        
        let swiftResponse = try CodableCBORDecoder().decode(CsrEnrollResponse.self, from: swiftData)
        let rustResponse = try CodableCBORDecoder().decode(CsrEnrollResponse.self, from: rustData)
        
        XCTAssertEqual(swiftResponse.network_id, rustResponse.network_id, "network_id mismatch")
        XCTAssertEqual(swiftResponse.certificate_der, rustResponse.certificate_der, "certificate_der mismatch")
        XCTAssertEqual(swiftResponse.issuing_ca_der, rustResponse.issuing_ca_der, "issuing_ca_der mismatch")
        XCTAssertEqual(swiftResponse.root_ca_der, rustResponse.root_ca_der, "root_ca_der mismatch")
        XCTAssertEqual(swiftResponse.expires_at, rustResponse.expires_at, "expires_at mismatch")
        
        print("✅ CsrEnrollResponse validation passed")
    }
    
    func testValidateCaErrorResponse() throws {
        print("🔍 Validating CaErrorResponse...")
        
        let swiftData = try readBytes(filename: "ca_error_response_basic.bin")
        let rustData = try readBytes(filename: "ca_error_response_basic.bin", isRust: true)
        
        let swiftError = try CodableCBORDecoder().decode(CaErrorResponse.self, from: swiftData)
        let rustError = try CodableCBORDecoder().decode(CaErrorResponse.self, from: rustData)
        
        XCTAssertEqual(swiftError.code, rustError.code, "code mismatch")
        XCTAssertEqual(swiftError.message, rustError.message, "message mismatch")
        XCTAssertEqual(swiftError.reason, rustError.reason, "reason mismatch")
        
        print("✅ CaErrorResponse validation passed")
    }
    
    // MARK: - Debug Tests (to identify specific CBOR issues)
    
    func testDebugEnrollmentTokenPermissions() throws {
        print("🔍 Debug: Testing EnrollmentToken permissions field...")
        
        // Create a test enrollment token with known permissions
        let testBody = EnrollmentTokenBody(
            token_id: "debug_token",
            network_id: "debug_network",
            subject_hint: "debug_subject",
            not_before: 1757890822,
            expires_at: 1757894422,
            nonce: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
            permissions: ["enroll"]
        )
        
        let testToken = EnrollmentToken(
            body: testBody,
            signature: Array(1...70),
            signer_id: "debug_signer"
        )
        
        // Encode to CBOR
        let cborData = try CodableCBOREncoder().encode(testToken)
        print("   📝 Encoded CBOR size: \(cborData.count) bytes")
        
        // Decode back from CBOR
        let decodedToken = try CodableCBORDecoder().decode(EnrollmentToken.self, from: cborData)
        
        // Check permissions field specifically
        print("   🔍 Original permissions: \(testToken.body.permissions)")
        print("   🔍 Decoded permissions: \(decodedToken.body.permissions)")
        
        // Check if permissions are corrupted
        if decodedToken.body.permissions != testToken.body.permissions {
            print("   ❌ PERMISSIONS CORRUPTION DETECTED!")
            print("   🔍 Original: \(testToken.body.permissions)")
            print("   🔍 Decoded:  \(decodedToken.body.permissions)")
            
            // Check individual characters
            for (index, (original, decoded)) in zip(testToken.body.permissions, decodedToken.body.permissions).enumerated() {
                if original != decoded {
                    print("   🔍 Permission[\(index)] mismatch:")
                    print("     Original: '\(original)' (bytes: \(Array(original.utf8)))")
                    print("     Decoded:  '\(decoded)' (bytes: \(Array(decoded.utf8)))")
                }
            }
        } else {
            print("   ✅ Permissions field is correct")
        }
        
        XCTAssertEqual(decodedToken.body.permissions, testToken.body.permissions, "Permissions field corruption detected")
    }
    
    // MARK: - Helper Functions
    
    private func readBytes(filename: String, isRust: Bool = false) throws -> Data {
        let baseDir = isRust ? "/Users/rafael/dev/runar-swift/runar-rust/rust-examples/target/ffi-types-vectors" : "/Users/rafael/dev/runar-swift/swift-ffi/target/ffi-types-vectors-swift"
        let fileURL = URL(fileURLWithPath: "\(baseDir)/\(filename)")
        return try Data(contentsOf: fileURL)
    }
}
