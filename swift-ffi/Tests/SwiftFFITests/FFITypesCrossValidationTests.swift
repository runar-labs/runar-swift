import Foundation
import SwiftCBOR
import SwiftCommon
@testable import SwiftFFI
import XCTest

final class FFITypesCrossValidationTests: XCTestCase {
    
    func testFFITypesCrossValidation() async throws {
        print("🔬 FFI Types CBOR Cross-Platform Validation")
        print("===========================================")
        
        // Check that both directories exist
        let swiftDir = URL(fileURLWithPath: "target/ffi-types-vectors-swift")
        let rustDir = URL(fileURLWithPath: "../../runar-rust/rust-examples/target/ffi-types-vectors")
        
        guard FileManager.default.fileExists(atPath: swiftDir.path) else {
            XCTFail("Swift FFI types vectors directory not found: \(swiftDir.path). Run Swift FFI types vectors first.")
            return
        }
        
        guard FileManager.default.fileExists(atPath: rustDir.path) else {
            XCTFail("Rust FFI types vectors directory not found: \(rustDir.path). Run Rust FFI types vectors first.")
            return
        }
        
        print("📁 Found FFI types vector directories:")
        print("   Swift: \(swiftDir.path)")
        print("   Rust:  \(rustDir.path)")
        
        print("\n🚀 Running FFI types validation tests...")
        
        // Run all validation tests
        let tests = [
            ("EnrollmentTokenBody", validateEnrollmentTokenBody),
            ("EnrollmentToken", validateEnrollmentToken),
            ("SetupToken", validateSetupToken),
            ("CsrEnrollRequest", validateCsrEnrollRequest),
            ("CsrEnrollResponse", validateCsrEnrollResponse),
            ("RenewRequest", validateRenewRequest),
            ("RenewResponse", validateRenewResponse),
            ("RevokeRequest", validateRevokeRequest),
            ("RevokeResponse", validateRevokeResponse),
            ("CaStatus", validateCaStatus),
            ("ChainResponse", validateChainResponse),
            ("CaErrorResponse", validateCaErrorResponse)
        ]
        
        var passed = 0
        var failed = 0
        
        for (name, test) in tests {
            do {
                try await test(swiftDir, rustDir)
                print("✅ \(name) validation passed")
                passed += 1
            } catch {
                print("❌ \(name) validation failed: \(error)")
                failed += 1
            }
        }
        
        print("\n📊 FFI Types Validation Results")
        print("================================")
        print("✅ Passed: \(passed)")
        print("❌ Failed: \(failed)")
        print("📈 Success Rate: \(String(format: "%.1f", (Double(passed) / Double(passed + failed)) * 100.0))%")
        
        if failed == 0 {
            print("\n🎉 All FFI types validations passed! Swift and Rust CBOR are compatible!")
        } else {
            print("\n⚠️  Some FFI types validations failed. Check the output above for details.")
            XCTFail("\(failed) FFI types validations failed")
        }
    }
    
    private func validateEnrollmentTokenBody(swiftDir: URL, rustDir: URL) async throws {
        let swiftData = try Data(contentsOf: swiftDir.appendingPathComponent("enrollment_token_body_basic.bin"))
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("enrollment_token_body_basic.bin"))
        
        let swiftBody: EnrollmentTokenBody = try CodableCBORDecoder().decode(EnrollmentTokenBody.self, from: swiftData)
        let rustBody: EnrollmentTokenBody = try CodableCBORDecoder().decode(EnrollmentTokenBody.self, from: rustData)
        
        // Verify both can be decoded and are equal
        XCTAssertEqual(swiftBody, rustBody, "EnrollmentTokenBody validation failed - Swift and Rust data don't match")
    }
    
    private func validateEnrollmentToken(swiftDir: URL, rustDir: URL) async throws {
        let swiftData = try Data(contentsOf: swiftDir.appendingPathComponent("enrollment_token_basic.bin"))
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("enrollment_token_basic.bin"))
        
        let swiftToken: EnrollmentToken = try CodableCBORDecoder().decode(EnrollmentToken.self, from: swiftData)
        let rustToken: EnrollmentToken = try CodableCBORDecoder().decode(EnrollmentToken.self, from: rustData)
        
        // Verify both can be decoded and are equal
        XCTAssertEqual(swiftToken, rustToken, "EnrollmentToken validation failed - Swift and Rust data don't match")
    }
    
    private func validateSetupToken(swiftDir: URL, rustDir: URL) async throws {
        let swiftData = try Data(contentsOf: swiftDir.appendingPathComponent("setup_token_basic.bin"))
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("setup_token_basic.bin"))
        
        let swiftSetup: SetupToken = try CodableCBORDecoder().decode(SetupToken.self, from: swiftData)
        let rustSetup: SetupToken = try CodableCBORDecoder().decode(SetupToken.self, from: rustData)
        
        // Verify both can be decoded and are equal
        XCTAssertEqual(swiftSetup, rustSetup, "SetupToken validation failed - Swift and Rust data don't match")
    }
    
    private func validateCsrEnrollRequest(swiftDir: URL, rustDir: URL) async throws {
        let swiftData = try Data(contentsOf: swiftDir.appendingPathComponent("csr_enroll_request_basic.bin"))
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("csr_enroll_request_basic.bin"))
        
        let swiftRequest: CsrEnrollRequest = try CodableCBORDecoder().decode(CsrEnrollRequest.self, from: swiftData)
        let rustRequest: CsrEnrollRequest = try CodableCBORDecoder().decode(CsrEnrollRequest.self, from: rustData)
        
        // Verify both can be decoded and are equal
        XCTAssertEqual(swiftRequest, rustRequest, "CsrEnrollRequest validation failed - Swift and Rust data don't match")
    }
    
    private func validateCsrEnrollResponse(swiftDir: URL, rustDir: URL) async throws {
        let swiftData = try Data(contentsOf: swiftDir.appendingPathComponent("csr_enroll_response_basic.bin"))
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("csr_enroll_response_basic.bin"))
        
        let swiftResponse: CsrEnrollResponse = try CodableCBORDecoder().decode(CsrEnrollResponse.self, from: swiftData)
        let rustResponse: CsrEnrollResponse = try CodableCBORDecoder().decode(CsrEnrollResponse.self, from: rustData)
        
        // Verify both can be decoded and are equal
        XCTAssertEqual(swiftResponse, rustResponse, "CsrEnrollResponse validation failed - Swift and Rust data don't match")
    }
    
    private func validateRenewRequest(swiftDir: URL, rustDir: URL) async throws {
        let swiftData = try Data(contentsOf: swiftDir.appendingPathComponent("renew_request_basic.bin"))
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("renew_request_basic.bin"))
        
        let swiftRequest: RenewRequest = try CodableCBORDecoder().decode(RenewRequest.self, from: swiftData)
        let rustRequest: RenewRequest = try CodableCBORDecoder().decode(RenewRequest.self, from: rustData)
        
        // Verify both can be decoded and are equal
        XCTAssertEqual(swiftRequest, rustRequest, "RenewRequest validation failed - Swift and Rust data don't match")
    }
    
    private func validateRenewResponse(swiftDir: URL, rustDir: URL) async throws {
        let swiftData = try Data(contentsOf: swiftDir.appendingPathComponent("renew_response_basic.bin"))
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("renew_response_basic.bin"))
        
        let swiftResponse: RenewResponse = try CodableCBORDecoder().decode(RenewResponse.self, from: swiftData)
        let rustResponse: RenewResponse = try CodableCBORDecoder().decode(RenewResponse.self, from: rustData)
        
        // Verify both can be decoded and are equal
        XCTAssertEqual(swiftResponse, rustResponse, "RenewResponse validation failed - Swift and Rust data don't match")
    }
    
    private func validateRevokeRequest(swiftDir: URL, rustDir: URL) async throws {
        let swiftData = try Data(contentsOf: swiftDir.appendingPathComponent("revoke_request_basic.bin"))
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("revoke_request_basic.bin"))
        
        let swiftRequest: RevokeRequest = try CodableCBORDecoder().decode(RevokeRequest.self, from: swiftData)
        let rustRequest: RevokeRequest = try CodableCBORDecoder().decode(RevokeRequest.self, from: rustData)
        
        // Verify both can be decoded and are equal
        XCTAssertEqual(swiftRequest, rustRequest, "RevokeRequest validation failed - Swift and Rust data don't match")
    }
    
    private func validateRevokeResponse(swiftDir: URL, rustDir: URL) async throws {
        let swiftData = try Data(contentsOf: swiftDir.appendingPathComponent("revoke_response_basic.bin"))
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("revoke_response_basic.bin"))
        
        let swiftResponse: RevokeResponse = try CodableCBORDecoder().decode(RevokeResponse.self, from: swiftData)
        let rustResponse: RevokeResponse = try CodableCBORDecoder().decode(RevokeResponse.self, from: rustData)
        
        // Verify both can be decoded and are equal
        XCTAssertEqual(swiftResponse, rustResponse, "RevokeResponse validation failed - Swift and Rust data don't match")
    }
    
    private func validateCaStatus(swiftDir: URL, rustDir: URL) async throws {
        let swiftData = try Data(contentsOf: swiftDir.appendingPathComponent("ca_status_basic.bin"))
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("ca_status_basic.bin"))
        
        let swiftStatus: CaStatus = try CodableCBORDecoder().decode(CaStatus.self, from: swiftData)
        let rustStatus: CaStatus = try CodableCBORDecoder().decode(CaStatus.self, from: rustData)
        
        // Verify both can be decoded and are equal
        XCTAssertEqual(swiftStatus, rustStatus, "CaStatus validation failed - Swift and Rust data don't match")
    }
    
    private func validateChainResponse(swiftDir: URL, rustDir: URL) async throws {
        let swiftData = try Data(contentsOf: swiftDir.appendingPathComponent("chain_response_basic.bin"))
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("chain_response_basic.bin"))
        
        let swiftResponse: ChainResponse = try CodableCBORDecoder().decode(ChainResponse.self, from: swiftData)
        let rustResponse: ChainResponse = try CodableCBORDecoder().decode(ChainResponse.self, from: rustData)
        
        // Verify both can be decoded and are equal
        XCTAssertEqual(swiftResponse, rustResponse, "ChainResponse validation failed - Swift and Rust data don't match")
    }
    
    
    private func validateCaErrorResponse(swiftDir: URL, rustDir: URL) async throws {
        let swiftData = try Data(contentsOf: swiftDir.appendingPathComponent("ca_error_response_basic.bin"))
        let rustData = try Data(contentsOf: rustDir.appendingPathComponent("ca_error_response_basic.bin"))
        
        let swiftError: CaErrorResponse = try CodableCBORDecoder().decode(CaErrorResponse.self, from: swiftData)
        let rustError: CaErrorResponse = try CodableCBORDecoder().decode(CaErrorResponse.self, from: rustData)
        
        // Verify both can be decoded and are equal
        XCTAssertEqual(swiftError, rustError, "CaErrorResponse validation failed - Swift and Rust data don't match")
    }
}
