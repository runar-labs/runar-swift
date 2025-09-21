import Foundation
import SwiftCBOR
import SwiftCommon
@testable import SwiftFFI
import XCTest

@available(macOS 12.0, *)
@MainActor
final class CANodeSetupTests: XCTestCase {
    func createLogger() -> RunarLogger { RunarLogger(component: .custom) }
    
    func encode<T: Codable>(_ value: T) throws -> Data { try CodableCBOREncoder().encode(value) }

    func testCANodeSetupWithValidEAKeys() async throws {
        // Test that setupComplete with valid EA keys generates certificates
        let caNode = try await CANode.create()
        let eaManager = EAKeyManager(logger: createLogger())
        let eaHandle = try await eaManager.createKeyPair()
        defer { EAKeyManager.free(eaHandle) }
        
        let eaPublicKeyCbor = try await eaManager.getPublicKey(eaHandle)
        
        // Convert Data to [UInt8] array as expected by Rust (Vec<Vec<u8>>)
        let eaPublicKeyArray = Array(eaPublicKeyCbor)
        
        // Wrap single EA key array in CBOR array as expected by Rust
        let eaKeysArrayCbor = try CodableCBOREncoder().encode([eaPublicKeyArray])
        
        // CRITICAL: Configure Enrollment Authority BEFORE setupComplete
        try await caNode.configureEnrollmentAuthority(eaPublicKeys: eaKeysArrayCbor)
        
        let setupParams = CANodeManager.CANodeSetupParams(
            caNode: caNode.ffiHandle,
            rootCaSubject: "CN=Test Root CA,O=Test,C=US",
            issuingCaSubject: "CN=Test Issuing CA,O=Test,C=US",
            validityDays: 365,
            issuingCaSerial: 1,
            eaPublicKeys: eaKeysArrayCbor,
            networkId: "test_network"
        )
        
        // This should succeed
        try await caNode.setupComplete(params: setupParams)
        
        // Certificates should be generated
        let rootCa = try await caNode.getRootCACertificate()
        let issuingCa = try await caNode.getIssuingCACertificate()
        
        // Assert certificates are not empty
        XCTAssertFalse(rootCa.isEmpty, "Root CA certificate should not be empty")
        XCTAssertFalse(issuingCa.isEmpty, "Issuing CA certificate should not be empty")
        
        // Assert reasonable certificate sizes (should be > 100 bytes)
        XCTAssertGreaterThan(rootCa.count, 100, "Root CA certificate should be substantial")
        XCTAssertGreaterThan(issuingCa.count, 100, "Issuing CA certificate should be substantial")
    }
    
    func testCANodeSetupWithInvalidEAKeys() async throws {
        // Test that setupComplete with invalid EA key format fails fast
        let caNode = try await CANode.create()
        
        // Create invalid EA keys (single key CBOR not wrapped in array)
        let invalidEaKeysCbor = Data([0x01, 0x02, 0x03]) // Invalid CBOR
        
        let setupParams = CANodeManager.CANodeSetupParams(
            caNode: caNode.ffiHandle,
            rootCaSubject: "CN=Test Root CA,O=Test,C=US",
            issuingCaSubject: "CN=Test Issuing CA,O=Test,C=US",
            validityDays: 365,
            issuingCaSerial: 1,
            eaPublicKeys: invalidEaKeysCbor,
            networkId: "test_network"
        )
        
        // This should fail with a descriptive error
        do {
            try await caNode.setupComplete(params: setupParams)
            XCTFail("setupComplete should have failed with invalid EA keys")
        } catch {
            // Should fail with a descriptive error about EA key format
            let errorMessage = error.localizedDescription
            XCTAssertTrue(errorMessage.contains("EA") || errorMessage.contains("public key") || errorMessage.contains("parse"), 
                         "Error should mention EA public key parsing issue: \(errorMessage)")
        }
    }
    
    func testCAClientRefusesEmptyCertificates() async throws {
        // Test that CAClient creation fails with empty certificates
        let nodeKeys = try await NodeKeyManager()
        
        // This should fail with a descriptive error during config creation
        do {
            let emptyConfig = try CaClientConfigAll(
                bootstrap_server: "127.0.0.1:8080",
                authenticated_server: "127.0.0.1:8081",
                network_id: "test_network",
                request_timeout_seconds: 30,
                max_retries: 3,
                root_ca_der: Data(), // Empty certificate
                issuing_ca_der: Data() // Empty certificate
            )
            XCTFail("CaClientConfigAll creation should have failed with empty certificates")
        } catch {
            // Should fail with a descriptive error about empty certificates
            let errorMessage = error.localizedDescription
            XCTAssertTrue(errorMessage.contains("root_ca_der") || errorMessage.contains("issuing_ca_der") || errorMessage.contains("empty"), 
                         "Error should mention empty certificate issue: \(errorMessage)")
        }
    }
}
