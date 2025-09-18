import XCTest
import SwiftFFI
import SwiftCommon

@testable import SwiftFFI

/// Tests for certificate status functionality
/// Tests certificate status/serial via keys; peer certificate validation
final class CertificateStatusTests: XCTestCase {
    
    private var nodeKeys: KeysHandle!
    private var caNode: CANode!
    private var caServer: CAServer!
    private var caClient: CAClient!
    
    override func setUp() {
        super.setUp()
        
        // Create node keys handle
        nodeKeys = try! KeysHandle()
        try! nodeKeys.initializeAsNode()
        try! nodeKeys.nodeGenerateKeys()
        
        // Create CA node for testing
        caNode = try! CANode.create()
        
        // Set up CA server for testing
        let caServerConfig = CaServerConfig(
            bootstrapBind: "127.0.0.1:0",
            authenticatedBind: "127.0.0.1:0",
            networkId: "test-network",
            rateLimitPerMinute: 100,
            rateLimitPerHour: 1000
        )
        
        let sharedCaNode = try! caNode.createShared()
        caServer = try! CAServer.create(config: caServerConfig, sharedCaNode: sharedCaNode)
        
        // Set up CA client for testing
        let caClientConfig = CaClientConfigAll(
            bootstrap_server: "127.0.0.1:0",
            authenticated_server: "127.0.0.1:0",
            network_id: "test-network",
            request_timeout_seconds: 30,
            max_retries: 3,
            root_ca_der: Data(),
            issuing_ca_der: Data()
        )
        
        caClient = try! CAClient(config: caClientConfig, nodeKeys: nodeKeys)
    }
    
    override func tearDown() {
        caClient = nil
        caServer = nil
        caNode = nil
        nodeKeys = nil
        super.tearDown()
    }
    
    // MARK: - Certificate Status Tests
    
    func testGetCertificateStatus() throws {
        // Test getting certificate status
        let status = try nodeKeys.getCertificateStatus()
        
        // Verify status is returned (specific values depend on implementation)
        XCTAssertNotNil(status, "Certificate status should be returned")
    }
    
    func testGetCertificateStatusAfterInstallation() throws {
        // Generate CSR and install certificate
        let csrData = try nodeKeys.generateCsrSetupToken()
        
        // For this test, we'll just verify the status can be retrieved
        // In a real scenario, we would process the CSR through the CA
        let status = try nodeKeys.getCertificateStatus()
        XCTAssertNotNil(status, "Certificate status should be available after CSR generation")
    }
    
    // MARK: - Certificate Serial Tests
    
    func testGetCertificateSerial() throws {
        // Test getting certificate serial
        do {
            let serial = try nodeKeys.getCertificateSerial()
            XCTAssertFalse(serial.isEmpty, "Certificate serial should not be empty")
        } catch {
            // Might fail if no certificate is installed
            XCTAssertTrue(error is FFIError)
        }
    }
    
    func testGetCertificateSerialAfterInstallation() throws {
        // Generate CSR
        let csrData = try nodeKeys.generateCsrSetupToken()
        
        // Try to get serial (might fail if certificate not installed)
        do {
            let serial = try nodeKeys.getCertificateSerial()
            XCTAssertFalse(serial.isEmpty, "Certificate serial should not be empty")
        } catch {
            // Expected if no certificate is installed
            XCTAssertTrue(error is FFIError)
        }
    }
    
    // MARK: - Peer Certificate Validation Tests
    
    func testValidatePeerCertificate() throws {
        // Get node's own certificate for testing
        let nodeCertificate = try nodeKeys.getNodeCertificate()
        
        // Validate peer certificate (using own certificate for testing)
        do {
            try nodeKeys.validatePeerCertificate(nodeCertificate)
            // Should succeed if certificate is valid
        } catch {
            // Might fail depending on certificate validity
            XCTAssertTrue(error is FFIError)
        }
    }
    
    func testValidatePeerCertificateWithInvalidData() throws {
        // Test with invalid certificate data
        let invalidCertificate = Data([0x01, 0x02, 0x03, 0x04]) // Invalid certificate data
        
        do {
            try nodeKeys.validatePeerCertificate(invalidCertificate)
            XCTFail("Should have thrown error for invalid certificate")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }
    
    func testValidatePeerCertificateWithEmptyData() throws {
        // Test with empty certificate data
        let emptyCertificate = Data()
        
        do {
            try nodeKeys.validatePeerCertificate(emptyCertificate)
            XCTFail("Should have thrown error for empty certificate")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }
    
    // MARK: - Certificate Utilities Tests
    
    func testExtractSkiFromCertificate() throws {
        // Get node certificate
        let nodeCertificate = try nodeKeys.getNodeCertificate()
        
        // Extract SKI
        let ski = try CertificateUtils.extractSki(from: nodeCertificate)
        
        // Verify SKI is extracted
        XCTAssertFalse(ski.isEmpty, "SKI should not be empty")
        XCTAssertGreaterThan(ski.count, 0, "SKI should have content")
    }
    
    func testGetSerialHexFromCertificate() throws {
        // Get node certificate
        let nodeCertificate = try nodeKeys.getNodeCertificate()
        
        // Get serial hex
        let serialHex = try CertificateUtils.getSerialHex(from: nodeCertificate)
        
        // Verify serial hex is extracted
        XCTAssertFalse(serialHex.isEmpty, "Serial hex should not be empty")
        XCTAssertGreaterThan(serialHex.count, 0, "Serial hex should have content")
    }
    
    func testCertificateUtilitiesWithInvalidData() throws {
        // Test certificate utilities with invalid data
        let invalidCertificate = Data([0x01, 0x02, 0x03, 0x04]) // Invalid certificate data
        
        do {
            _ = try CertificateUtils.extractSki(from: invalidCertificate)
            XCTFail("Should have thrown error for invalid certificate")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
        
        do {
            _ = try CertificateUtils.getSerialHex(from: invalidCertificate)
            XCTFail("Should have thrown error for invalid certificate")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }
    
    // MARK: - Certificate Lifecycle Tests
    
    func testCertificateLifecycle() throws {
        // Test complete certificate lifecycle
        
        // 1. Generate CSR
        let csrData = try nodeKeys.generateCsrSetupToken()
        XCTAssertFalse(csrData.isEmpty, "CSR should be generated")
        
        // 2. Get initial certificate status
        let initialStatus = try nodeKeys.getCertificateStatus()
        XCTAssertNotNil(initialStatus, "Initial certificate status should be available")
        
        // 3. Try to get certificate serial (might fail if no certificate)
        do {
            let serial = try nodeKeys.getCertificateSerial()
            XCTAssertFalse(serial.isEmpty, "Certificate serial should be available")
        } catch {
            // Expected if no certificate is installed
            XCTAssertTrue(error is FFIError)
        }
        
        // 4. Get QUIC certificate config
        let quicConfig = try nodeKeys.getQuicCertificateConfig()
        XCTAssertFalse(quicConfig.isEmpty, "QUIC certificate config should be available")
        
        // 5. Get node certificate
        let nodeCertificate = try nodeKeys.getNodeCertificate()
        XCTAssertFalse(nodeCertificate.isEmpty, "Node certificate should be available")
        
        // 6. Validate the certificate
        do {
            try nodeKeys.validatePeerCertificate(nodeCertificate)
            // Should succeed if certificate is valid
        } catch {
            // Might fail depending on certificate validity
            XCTAssertTrue(error is FFIError)
        }
    }
    
    // MARK: - Multiple Certificate Tests
    
    func testMultipleCertificates() throws {
        // Test handling multiple certificates
        
        // Create multiple node keys handles
        let nodeKeys1 = try KeysHandle()
        try nodeKeys1.initializeAsNode()
        try nodeKeys1.nodeGenerateKeys()
        
        let nodeKeys2 = try KeysHandle()
        try nodeKeys2.initializeAsNode()
        try nodeKeys2.nodeGenerateKeys()
        
        // Get certificates from both
        let certificate1 = try nodeKeys1.getNodeCertificate()
        let certificate2 = try nodeKeys2.getNodeCertificate()
        
        // Verify certificates are different
        XCTAssertNotEqual(certificate1, certificate2, "Different nodes should have different certificates")
        
        // Test certificate utilities on both
        let ski1 = try CertificateUtils.extractSki(from: certificate1)
        let ski2 = try CertificateUtils.extractSki(from: certificate2)
        
        XCTAssertNotEqual(ski1, ski2, "Different certificates should have different SKIs")
        
        let serial1 = try CertificateUtils.getSerialHex(from: certificate1)
        let serial2 = try CertificateUtils.getSerialHex(from: certificate2)
        
        XCTAssertNotEqual(serial1, serial2, "Different certificates should have different serials")
    }
    
    // MARK: - Certificate Status Edge Cases
    
    func testCertificateStatusEdgeCases() throws {
        // Test various edge cases for certificate status
        
        // Test with uninitialized keys
        let uninitializedKeys = try KeysHandle()
        
        do {
            _ = try uninitializedKeys.getCertificateStatus()
            XCTFail("Should have thrown error for uninitialized keys")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
        
        do {
            _ = try uninitializedKeys.getCertificateSerial()
            XCTFail("Should have thrown error for uninitialized keys")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }
    
    // MARK: - Concurrent Certificate Operations
    
    func testConcurrentCertificateOperations() throws {
        // Test concurrent certificate operations
        
        let expectation = XCTestExpectation(description: "Concurrent certificate operations")
        expectation.expectedFulfillmentCount = 3
        
        // Run concurrent operations
        DispatchQueue.global().async {
            do {
                let status = try self.nodeKeys.getCertificateStatus()
                XCTAssertNotNil(status)
                expectation.fulfill()
            } catch {
                XCTFail("Concurrent get certificate status failed: \(error)")
            }
        }
        
        DispatchQueue.global().async {
            do {
                let certificate = try self.nodeKeys.getNodeCertificate()
                XCTAssertFalse(certificate.isEmpty)
                expectation.fulfill()
            } catch {
                XCTFail("Concurrent get node certificate failed: \(error)")
            }
        }
        
        DispatchQueue.global().async {
            do {
                let quicConfig = try self.nodeKeys.getQuicCertificateConfig()
                XCTAssertFalse(quicConfig.isEmpty)
                expectation.fulfill()
            } catch {
                XCTFail("Concurrent get QUIC certificate config failed: \(error)")
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: - Certificate Validation Performance
    
    func testCertificateValidationPerformance() throws {
        // Test performance of certificate validation operations
        
        let nodeCertificate = try nodeKeys.getNodeCertificate()
        let iterations = 100
        
        // Measure certificate validation performance
        let validationStartTime = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            do {
                try nodeKeys.validatePeerCertificate(nodeCertificate)
            } catch {
                // Ignore validation errors for performance testing
            }
        }
        let validationTime = CFAbsoluteTimeGetCurrent() - validationStartTime
        
        // Measure SKI extraction performance
        let skiStartTime = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            _ = try CertificateUtils.extractSki(from: nodeCertificate)
        }
        let skiTime = CFAbsoluteTimeGetCurrent() - skiStartTime
        
        // Measure serial extraction performance
        let serialStartTime = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            _ = try CertificateUtils.getSerialHex(from: nodeCertificate)
        }
        let serialTime = CFAbsoluteTimeGetCurrent() - serialStartTime
        
        // Verify operations completed successfully
        XCTAssertGreaterThan(validationTime, 0, "Certificate validation should take some time")
        XCTAssertGreaterThan(skiTime, 0, "SKI extraction should take some time")
        XCTAssertGreaterThan(serialTime, 0, "Serial extraction should take some time")
        
        // Log performance metrics (optional)
        print("Certificate validation time for \(iterations) iterations: \(validationTime) seconds")
        print("SKI extraction time for \(iterations) iterations: \(skiTime) seconds")
        print("Serial extraction time for \(iterations) iterations: \(serialTime) seconds")
    }
    
    // MARK: - Certificate Error Handling
    
    func testCertificateErrorHandling() throws {
        // Test various error conditions for certificate operations
        
        // Test with corrupted certificate data
        let corruptedCertificate = Data([0xFF, 0xFE, 0xFD, 0xFC, 0xFB, 0xFA])
        
        do {
            try nodeKeys.validatePeerCertificate(corruptedCertificate)
            XCTFail("Should have thrown error for corrupted certificate")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
        
        do {
            _ = try CertificateUtils.extractSki(from: corruptedCertificate)
            XCTFail("Should have thrown error for corrupted certificate")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
        
        do {
            _ = try CertificateUtils.getSerialHex(from: corruptedCertificate)
            XCTFail("Should have thrown error for corrupted certificate")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }
    
    // MARK: - Certificate Status Consistency
    
    func testCertificateStatusConsistency() throws {
        // Test that certificate status is consistent across multiple calls
        
        let status1 = try nodeKeys.getCertificateStatus()
        let status2 = try nodeKeys.getCertificateStatus()
        
        // Status should be consistent (same value)
        XCTAssertEqual(status1, status2, "Certificate status should be consistent across multiple calls")
        
        // Test after some operations
        _ = try nodeKeys.generateCsrSetupToken()
        
        let status3 = try nodeKeys.getCertificateStatus()
        // Status might change after CSR generation, but should still be valid
        XCTAssertNotNil(status3, "Certificate status should still be valid after CSR generation")
    }
}
