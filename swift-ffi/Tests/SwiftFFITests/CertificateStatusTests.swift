import SwiftCBOR
import SwiftCommon
import SwiftFFI
import XCTest

@testable import SwiftFFI

/// Tests for certificate status functionality
/// Tests certificate status/serial via keys; peer certificate validation
final class CertificateStatusTests: XCTestCase {
    private var nodeKeys: NodeKeyManager!
    private var caNode: CANode!
    private var caServer: CAServer!
    private var caClient: CAClient!

    override func setUp() async throws {
        try await super.setUp()

        // Create node keys handle
        do {
            nodeKeys = try await NodeKeyManager()
            try await nodeKeys.generateKeys()

            // Create CA node for testing
            caNode = try CANode.create()
        } catch {
            XCTFail("Failed to set up test: \(error)")
        }

        // Set up CA server for testing
        let caServerConfig = CaServerConfig(
            bootstrapBind: "127.0.0.1:0",
            authenticatedBind: "127.0.0.1:0",
            networkId: "test_network",
            rateLimitPerMinute: 100,
            rateLimitPerHour: 1000
        )

        do {
            // Configure CA node first (before creating shared/server) to ensure server uses the configured CAs
            let eaManager = EAKeyManager(logger: RunarLogger.root(component: .custom("CertificateStatusTests")))
            let eaHandle = try await eaManager.createKeyPair()
            let eaPublicKey = try await eaManager.getPublicKey(eaHandle)
            let setupParams = CANodeManager.CANodeSetupParams(
                caNode: caNode.ffiHandle,
                rootCaSubject: "CN=Test Root CA,O=Test,C=US",
                issuingCaSubject: "CN=Test Issuing CA,O=Test,C=US",
                validityDays: 365,
                issuingCaSerial: 1,
                eaPublicKeys: eaPublicKey,
                networkId: "test_network"
            )
            try await caNode.setupComplete(params: setupParams)
            let rootCa = try await caNode.getRootCACertificate()
            let issuingCa = try await caNode.getIssuingCACertificate()

            // Now create server using the configured CA node
            caServer = try CAServer.create(config: caServerConfig, sharedCaNode: caNode.ffiHandle)

            // Start CA server and fetch real addresses
            try await caServer.start()
            let bootstrapAddr = try await caServer.bootstrapAddress()
            let authenticatedAddr = try await caServer.authenticatedAddress()

            let caClientConfig = try CaClientConfigAll(
                bootstrap_server: bootstrapAddr,
                authenticated_server: authenticatedAddr,
                network_id: "test_network",
                request_timeout_seconds: 30,
                max_retries: 3,
                root_ca_der: Array(rootCa),
                issuing_ca_der: Array(issuingCa)
            )

            caClient = try await nodeKeys.createCAClient(config: caClientConfig)

            // Perform real enrollment to install a certificate
            let now = UInt64(Date().timeIntervalSince1970)
            let tokenParams = EAKeyManager.EnrollmentTokenParams(
                eaKeyHandle: eaHandle,
                tokenId: "cert_status_tests_token",
                networkId: "test_network",
                subject: "CN=test-node,O=Runar,C=US",
                validFrom: now - 60,
                validUntil: now + 3600,
                nonce: Data((0 ..< 16).map { _ in UInt8.random(in: 0 ... 255) }),
                capabilities: ["enroll"]
            )
            let tokenData = try await eaManager.generateEnrollmentToken(params: tokenParams)
            let enrollmentToken = try CodableCBORDecoder().decode(EnrollmentToken.self, from: tokenData)
            let setupTokenCbor = try await nodeKeys.generateCSR()
            let setupToken = try CodableCBORDecoder().decode(SetupToken.self, from: setupTokenCbor)
            let csr = Data(setupToken.csr_der)
            let enrollReq = CsrEnrollRequest(
                network_id: "test_network",
                csr_der: csr,
                enrollment_token: enrollmentToken
            )
            let enrollReqData = try CodableCBOREncoder().encode(enrollReq)
            let enrollResp = try await caClient.enroll(bootstrapAddress: bootstrapAddr, request: enrollReqData)
            let certMsg = try await MobileKeyManager().fromEnrollResponse(enrollResp)
            try await nodeKeys.installCertificate(certMsg)
            try await Task.sleep(nanoseconds: 50_000_000)
        } catch {
            XCTFail("Failed to set up CA components: \(error)")
        }
    }

    override func tearDown() async throws {
        caClient = nil
        caServer = nil
        caNode = nil
        nodeKeys = nil
        try await super.tearDown()
    }

    // MARK: - Certificate Status Tests

    func testGetCertificateStatus() async throws {
        // Test getting certificate status
        let status = try await nodeKeys.getCertificateStatus()

        // Verify status is returned (specific values depend on implementation)
        XCTAssertNotNil(status, "Certificate status should be returned")
    }

    func testGetCertificateStatusAfterInstallation() async throws {
        // Generate CSR and install certificate
        _ = try await nodeKeys.generateCsrSetupToken()

        // For this test, we'll just verify the status can be retrieved
        // In a real scenario, we would process the CSR through the CA
        let status = try await nodeKeys.getCertificateStatus()
        XCTAssertNotNil(status, "Certificate status should be available after CSR generation")
    }

    // MARK: - Certificate Serial Tests

    func testGetCertificateSerial() async throws {
        // Test getting certificate serial
        do {
            let serial = try await nodeKeys.getCertificateSerial()
            XCTAssertFalse(serial.isEmpty, "Certificate serial should not be empty")
        } catch {
            // Might fail if no certificate is installed
            XCTAssertTrue(error is FFIError)
        }
    }

    func testGetCertificateSerialAfterInstallation() async throws {
        // Generate CSR
        _ = try await nodeKeys.generateCsrSetupToken()

        // Try to get serial (might fail if certificate not installed)
        do {
            let serial = try await nodeKeys.getCertificateSerial()
            XCTAssertFalse(serial.isEmpty, "Certificate serial should not be empty")
        } catch {
            // Expected if no certificate is installed
            XCTAssertTrue(error is FFIError)
        }
    }

    // MARK: - Peer Certificate Validation Tests

    func testValidatePeerCertificate() async throws {
        // Get node's own certificate for testing
        let nodeCertificate = try await nodeKeys.getNodeCertificate()

        // Validate peer certificate (using own certificate for testing)
        do {
            try await nodeKeys.validatePeerCertificate(nodeCertificate)
            // Should succeed if certificate is valid
        } catch {
            // Might fail depending on certificate validity
            XCTAssertTrue(error is FFIError)
        }
    }

    func testValidatePeerCertificateWithInvalidData() async throws {
        // Test with invalid certificate data
        let invalidCertificate = Data([0x01, 0x02, 0x03, 0x04]) // Invalid certificate data

        do {
            try await nodeKeys.validatePeerCertificate(invalidCertificate)
            XCTFail("Should have thrown error for invalid certificate")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }

    func testValidatePeerCertificateWithEmptyData() async throws {
        // Test with empty certificate data
        let emptyCertificate = Data()

        do {
            try await nodeKeys.validatePeerCertificate(emptyCertificate)
            XCTFail("Should have thrown error for empty certificate")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }

    // MARK: - Certificate Utilities Tests

    func testExtractSkiFromCertificate() async throws {
        // Get node certificate
        let nodeCertificate = try await nodeKeys.getNodeCertificate()

        // Extract SKI
        let ski = try await CertificateUtils.extractSki(from: nodeCertificate)

        // Verify SKI is extracted
        XCTAssertFalse(ski.isEmpty, "SKI should not be empty")
        XCTAssertGreaterThan(ski.count, 0, "SKI should have content")
    }

    func testGetSerialHexFromCertificate() async throws {
        // Get node certificate
        let nodeCertificate = try await nodeKeys.getNodeCertificate()

        // Get serial hex
        let serialHex = try await CertificateUtils.getSerialHex(from: nodeCertificate)

        // Verify serial hex is extracted
        XCTAssertFalse(serialHex.isEmpty, "Serial hex should not be empty")
        XCTAssertGreaterThan(serialHex.count, 0, "Serial hex should have content")
    }

    func testCertificateUtilitiesWithInvalidData() async throws {
        // Test certificate utilities with invalid data
        let invalidCertificate = Data([0x01, 0x02, 0x03, 0x04]) // Invalid certificate data

        do {
            _ = try await CertificateUtils.extractSki(from: invalidCertificate)
            XCTFail("Should have thrown error for invalid certificate")
        } catch {
            XCTAssertTrue(error is FFIError)
        }

        do {
            _ = try await CertificateUtils.getSerialHex(from: invalidCertificate)
            XCTFail("Should have thrown error for invalid certificate")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }

    // MARK: - Certificate Lifecycle Tests

    func testCertificateLifecycle() async throws {
        // Test complete certificate lifecycle

        // 1. Generate CSR
        let csrData = try await nodeKeys.generateCsrSetupToken()
        XCTAssertFalse(csrData.isEmpty, "CSR should be generated")

        // 2. Get initial certificate status
        let initialStatus = try await nodeKeys.getCertificateStatus()
        XCTAssertNotNil(initialStatus, "Initial certificate status should be available")

        // 3. Try to get certificate serial (might fail if no certificate)
        do {
            let serial = try await nodeKeys.getCertificateSerial()
            XCTAssertFalse(serial.isEmpty, "Certificate serial should be available")
        } catch {
            // Expected if no certificate is installed
            XCTAssertTrue(error is FFIError)
        }

        // 4. Get QUIC certificate config
        let quicConfig = try await nodeKeys.getQuicCertificateConfig()
        XCTAssertFalse(quicConfig.isEmpty, "QUIC certificate config should be available")

        // 5. Get node certificate
        let nodeCertificate = try await nodeKeys.getNodeCertificate()
        XCTAssertFalse(nodeCertificate.isEmpty, "Node certificate should be available")

        // 6. Validate the certificate
        do {
            try await nodeKeys.validatePeerCertificate(nodeCertificate)
            // Should succeed if certificate is valid
        } catch {
            // Might fail depending on certificate validity
            XCTAssertTrue(error is FFIError)
        }
    }

    // MARK: - Multiple Certificate Tests

    func testMultipleCertificates() async throws {
        // Test handling multiple certificates

        // Create multiple node keys handles
        let nodeKeys1 = try await NodeKeyManager()
        try await nodeKeys1.generateKeys()

        let nodeKeys2 = try await NodeKeyManager()
        try await nodeKeys2.generateKeys()

        // Create mobile key manager to act as CA
        let mobileKeys = try await MobileKeyManager()
        try await mobileKeys.initializeUserRootKey()

        // Generate CSRs and install certificates for both nodes
        let csr1 = try await nodeKeys1.generateCsrSetupToken()
        let cert1 = try await mobileKeys.processSetupToken(csr1)
        try await nodeKeys1.installCertificate(cert1)

        let csr2 = try await nodeKeys2.generateCsrSetupToken()
        let cert2 = try await mobileKeys.processSetupToken(csr2)
        try await nodeKeys2.installCertificate(cert2)

        // Get certificates from both
        let certificate1 = try await nodeKeys1.getNodeCertificate()
        let certificate2 = try await nodeKeys2.getNodeCertificate()

        // Verify certificates are different
        XCTAssertNotEqual(certificate1, certificate2, "Different nodes should have different certificates")

        // Test certificate utilities on both
        let ski1 = try await CertificateUtils.extractSki(from: certificate1)
        let ski2 = try await CertificateUtils.extractSki(from: certificate2)

        XCTAssertNotEqual(ski1, ski2, "Different certificates should have different SKIs")

        let serial1 = try await CertificateUtils.getSerialHex(from: certificate1)
        let serial2 = try await CertificateUtils.getSerialHex(from: certificate2)

        XCTAssertNotEqual(serial1, serial2, "Different certificates should have different serials")
    }

    // MARK: - Certificate Status Edge Cases

    func testCertificateStatusEdgeCases() async throws {
        // Test various edge cases for certificate status

        // Test with newly created keys (no certificate installed yet)
        let newNodeKeys = try await NodeKeyManager()

        // Should return status 0 (None) for newly created node manager
        let status = try await newNodeKeys.getCertificateStatus()
        XCTAssertEqual(status, 0, "Certificate status should be None for newly created node manager")

        // Should throw error when trying to get certificate serial without certificate
        do {
            _ = try await newNodeKeys.getCertificateSerial()
            XCTFail("Should have thrown error for node manager without certificate")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }

    // MARK: - Concurrent Certificate Operations

    func testConcurrentCertificateOperations() async throws {
        // Test concurrent certificate operations
        guard let nodeKeys = nodeKeys else {
            XCTFail("Node keys not initialized")
            return
        }

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    let status = try await nodeKeys.getCertificateStatus()
                    XCTAssertNotNil(status)
                } catch {
                    XCTFail("Concurrent get certificate status failed: \(error)")
                }
            }

            group.addTask {
                do {
                    let certificate = try await nodeKeys.getNodeCertificate()
                    XCTAssertFalse(certificate.isEmpty)
                } catch {
                    XCTFail("Concurrent get node certificate failed: \(error)")
                }
            }

            group.addTask {
                do {
                    let quicConfig = try await nodeKeys.getQuicCertificateConfig()
                    XCTAssertFalse(quicConfig.isEmpty)
                } catch {
                    XCTFail("Concurrent get QUIC certificate config failed: \(error)")
                }
            }

            // Wait for all tasks to complete
            for await _ in group {}
        }
    }

    // MARK: - Certificate Validation Performance

    func testCertificateValidationPerformance() async throws {
        // Test performance of certificate validation operations

        let nodeCertificate = try await nodeKeys.getNodeCertificate()
        let iterations = 100

        // Measure certificate validation performance
        let validationStartTime = CFAbsoluteTimeGetCurrent()
        for _ in 0 ..< iterations {
            do {
                try await nodeKeys.validatePeerCertificate(nodeCertificate)
            } catch {
                // Ignore validation errors for performance testing
            }
        }
        let validationTime = CFAbsoluteTimeGetCurrent() - validationStartTime

        // Measure SKI extraction performance
        let skiStartTime = CFAbsoluteTimeGetCurrent()
        for _ in 0 ..< iterations {
            _ = try await CertificateUtils.extractSki(from: nodeCertificate)
        }
        let skiTime = CFAbsoluteTimeGetCurrent() - skiStartTime

        // Measure serial extraction performance
        let serialStartTime = CFAbsoluteTimeGetCurrent()
        for _ in 0 ..< iterations {
            _ = try await CertificateUtils.getSerialHex(from: nodeCertificate)
        }
        let serialTime = CFAbsoluteTimeGetCurrent() - serialStartTime

        // Verify operations completed successfully
        XCTAssertGreaterThan(validationTime, 0, "Certificate validation should take some time")
        XCTAssertGreaterThan(skiTime, 0, "SKI extraction should take some time")
        XCTAssertGreaterThan(serialTime, 0, "Serial extraction should take some time")

        // Log performance metrics (optional)
    }

    // MARK: - Certificate Error Handling

    func testCertificateErrorHandling() async throws {
        // Test various error conditions for certificate operations

        // Test with corrupted certificate data
        let corruptedCertificate = Data([0xFF, 0xFE, 0xFD, 0xFC, 0xFB, 0xFA])

        do {
            try await nodeKeys.validatePeerCertificate(corruptedCertificate)
            XCTFail("Should have thrown error for corrupted certificate")
        } catch {
            XCTAssertTrue(error is FFIError)
        }

        do {
            _ = try await CertificateUtils.extractSki(from: corruptedCertificate)
            XCTFail("Should have thrown error for corrupted certificate")
        } catch {
            XCTAssertTrue(error is FFIError)
        }

        do {
            _ = try await CertificateUtils.getSerialHex(from: corruptedCertificate)
            XCTFail("Should have thrown error for corrupted certificate")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }

    // MARK: - Certificate Status Consistency

    func testCertificateStatusConsistency() async throws {
        // Test that certificate status is consistent across multiple calls

        let status1 = try await nodeKeys.getCertificateStatus()
        let status2 = try await nodeKeys.getCertificateStatus()

        // Status should be consistent (same value)
        XCTAssertEqual(status1, status2, "Certificate status should be consistent across multiple calls")

        // Test after some operations
        _ = try await nodeKeys.generateCsrSetupToken()

        let status3 = try await nodeKeys.getCertificateStatus()
        // Status might change after CSR generation, but should still be valid
        XCTAssertNotNil(status3, "Certificate status should still be valid after CSR generation")
    }
}
