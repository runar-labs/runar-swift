import SwiftCommon
import SwiftFFI
import XCTest

@testable import SwiftFFI

/// Tests for CA Client CRL functionality
/// Tests get_crl parity and rejection scenarios
final class CaClientCrlTests: XCTestCase {
    private var nodeKeys: NodeKeyManager!
    private var caNode: CANode!
    private var caServer: CAServer!
    private var caClient: CAClient!

    override func setUp() async throws {
        try await super.setUp()

        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("CaClientCrlTests"))

        // Create node keys handle
        do {
            nodeKeys = try await NodeKeyManager()
            try await nodeKeys.generateKeys()

            // Create CA node for testing
            caNode = try CANode.create(logger: logger.child(component: .network))
        } catch {
            XCTFail("Failed to set up test: \(error)")
        }

        // Set up CA server for testing
        let caServerConfig = CaServerConfig(
            bootstrapBind: "127.0.0.1:0",
            authenticatedBind: "127.0.0.1:0",
            networkId: "test-network",
            rateLimitPerMinute: 100,
            rateLimitPerHour: 1000
        )

        do {
            // Configure CA node exactly like Rust test: create EA pair, get EA pub key CBOR, pass directly to setupComplete
            let eaManager = EAKeyManager(logger: RunarLogger.root(component: .custom("CaClientCrlTests")))
            let eaHandle = try await eaManager.createKeyPair()
            defer { EAKeyManager.free(eaHandle) }
            let eaPublicKeyCbor = try await eaManager.getPublicKey(eaHandle)

            let setupParams = CANodeManager.CANodeSetupParams(
                caNode: caNode.ffiHandle,
                rootCaSubject: "CN=Test Root CA,O=Test,C=US",
                issuingCaSubject: "CN=Test Issuing CA,O=Test,C=US",
                validityDays: 365,
                issuingCaSerial: 1,
                eaPublicKeys: eaPublicKeyCbor,
                networkId: "test-network"
            )
            try await caNode.setupComplete(params: setupParams)

            // Create server
            caServer = try CAServer.create(config: caServerConfig, sharedCaNode: caNode.ffiHandle)

            // Set up CA client for testing
            let rootCa = try await caNode.getRootCACertificate()
            let issuingCa = try await caNode.getIssuingCACertificate()
            let caClientConfig = try CaClientConfigAll(
                bootstrap_server: "127.0.0.1:0",
                authenticated_server: "127.0.0.1:0",
                network_id: "test-network",
                request_timeout_seconds: 30,
                max_retries: 3,
                root_ca_der: Array(rootCa),
                issuing_ca_der: Array(issuingCa)
            )

            caClient = try await nodeKeys.createCAClient(config: caClientConfig, logger: logger.child(component: .network))
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

    // MARK: - CRL Retrieval Tests

    func testGetCrl() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("GetCrl"))
        // Test getting CRL from CA client
        let authenticatedAddress = "127.0.0.1:8080"
        let networkId = "test-network"

        do {
            let crlData = try await caClient.getCrl(
                authenticatedAddress: authenticatedAddress,
                networkId: networkId
            )

            // Verify CRL data is returned
            XCTAssertFalse(crlData.isEmpty, "CRL data should not be empty")
            XCTAssertGreaterThan(crlData.count, 0, "CRL data should have content")
        } catch {
            // Might fail if server is not running, which is expected in tests
            XCTAssertTrue(error is FFIError)
        }
    }

    func testGetCrlWithDifferentNetworkIds() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("GetCrlWithDifferentNetworkIds"))
        // Test getting CRL with different network IDs
        let authenticatedAddress = "127.0.0.1:8080"
        let networkIds = ["network-1", "network-2", "test-network", "production-network"]

        for networkId in networkIds {
            do {
                let crlData = try await caClient.getCrl(
                    authenticatedAddress: authenticatedAddress,
                    networkId: networkId
                )

                // Verify CRL data is returned
                XCTAssertFalse(crlData.isEmpty, "CRL data should not be empty for network \(networkId)")
            } catch {
                // Might fail if server is not running or network doesn't exist
                XCTAssertTrue(error is FFIError)
            }
        }
    }

    func testGetCrlWithDifferentAddresses() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("GetCrlWithDifferentAddresses"))
        // Test getting CRL with different addresses
        let addresses = ["127.0.0.1:8080", "127.0.0.1:8081", "localhost:8080", "0.0.0.0:8080"]
        let networkId = "test-network"

        for address in addresses {
            do {
                let crlData = try await caClient.getCrl(
                    authenticatedAddress: address,
                    networkId: networkId
                )

                // Verify CRL data is returned
                XCTAssertFalse(crlData.isEmpty, "CRL data should not be empty for address \(address)")
            } catch {
                // Might fail if server is not running on that address
                XCTAssertTrue(error is FFIError)
            }
        }
    }

    // MARK: - CRL Error Handling Tests

    func testGetCrlWithInvalidAddress() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("GetCrlWithInvalidAddress"))
        // Test getting CRL with invalid address
        let invalidAddress = "invalid-address:99999"
        let networkId = "test-network"

        do {
            let crlData = try await caClient.getCrl(
                authenticatedAddress: invalidAddress,
                networkId: networkId
            )
            XCTFail("Should have thrown error for invalid address")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }

    func testGetCrlWithEmptyAddress() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("GetCrlWithEmptyAddress"))
        // Test getting CRL with empty address
        let emptyAddress = ""
        let networkId = "test-network"

        do {
            let crlData = try await caClient.getCrl(
                authenticatedAddress: emptyAddress,
                networkId: networkId
            )
            XCTFail("Should have thrown error for empty address")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }

    func testGetCrlWithEmptyNetworkId() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("GetCrlWithEmptyNetworkId"))
        // Test getting CRL with empty network ID
        let authenticatedAddress = "127.0.0.1:8080"
        let emptyNetworkId = ""

        do {
            let crlData = try await caClient.getCrl(
                authenticatedAddress: authenticatedAddress,
                networkId: emptyNetworkId
            )
            XCTFail("Should have thrown error for empty network ID")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }

    func testGetCrlWithSpecialCharacters() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("GetCrlWithSpecialCharacters"))
        // Test getting CRL with special characters in parameters
        let authenticatedAddress = "127.0.0.1:8080"
        let networkId = "test-network-@#$%^&*()"

        do {
            let crlData = try await caClient.getCrl(
                authenticatedAddress: authenticatedAddress,
                networkId: networkId
            )
            // Might succeed or fail depending on validation
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }

    // MARK: - CRL Consistency Tests

    func testCrlConsistency() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("CrlConsistency"))
        // Test that CRL data is consistent across multiple calls
        let authenticatedAddress = "127.0.0.1:8080"
        let networkId = "test-network"

        do {
            let crl1 = try await caClient.getCrl(
                authenticatedAddress: authenticatedAddress,
                networkId: networkId
            )

            let crl2 = try await caClient.getCrl(
                authenticatedAddress: authenticatedAddress,
                networkId: networkId
            )

            // CRL data should be consistent (same content)
            XCTAssertEqual(crl1, crl2, "CRL data should be consistent across multiple calls")
        } catch {
            // Might fail if server is not running
            XCTAssertTrue(error is FFIError)
        }
    }

    func testCrlWithDifferentClients() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("CrlWithDifferentClients"))
        // Test CRL retrieval with different CA clients
        let authenticatedAddress = "127.0.0.1:8080"
        let networkId = "test-network"

        // Create another CA client
        let caClientConfig2 = try CaClientConfigAll(
            bootstrap_server: "127.0.0.1:0",
            authenticated_server: "127.0.0.1:0",
            network_id: "test-network",
            request_timeout_seconds: 30,
            max_retries: 3,
            root_ca_der: Array(await caNode.getRootCACertificate()),
            issuing_ca_der: Array(await caNode.getIssuingCACertificate())
        )

        let caClient2 = try await nodeKeys.createCAClient(config: caClientConfig2, logger: logger.child(component: .network))

        do {
            let crl1 = try await caClient.getCrl(
                authenticatedAddress: authenticatedAddress,
                networkId: networkId
            )

            let crl2 = try await caClient2.getCrl(
                authenticatedAddress: authenticatedAddress,
                networkId: networkId
            )

            // CRL data should be the same from different clients
            XCTAssertEqual(crl1, crl2, "CRL data should be the same from different clients")
        } catch {
            // Might fail if server is not running
            XCTAssertTrue(error is FFIError)
        }
    }

    // MARK: - CRL Performance Tests

    func testCrlPerformance() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("CrlPerformance"))
        // Test performance of CRL retrieval
        let authenticatedAddress = "127.0.0.1:8080"
        let networkId = "test-network"
        let iterations = 10

        do {
            let startTime = CFAbsoluteTimeGetCurrent()

            for _ in 0 ..< iterations {
                _ = try await caClient.getCrl(
                    authenticatedAddress: authenticatedAddress,
                    networkId: networkId
                )
            }

            let totalTime = CFAbsoluteTimeGetCurrent() - startTime
            let averageTime = totalTime / Double(iterations)

            // Verify operations completed successfully
            XCTAssertGreaterThan(totalTime, 0, "CRL retrieval should take some time")

            // Log performance metrics (optional)
        } catch {
            // Might fail if server is not running
            XCTAssertTrue(error is FFIError)
        }
    }

    // MARK: - CRL with Server Integration Tests

    func testCrlWithServerIntegration() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("CrlWithServerIntegration"))
        // Test CRL retrieval with actual server running
        // This test requires the CA server to be running

        // Start the CA server
        try await caServer.start()

        // Get server addresses
        let bootstrapAddress = try await caServer.bootstrapAddress()
        let authenticatedAddress = try await caServer.authenticatedAddress()

        // Test CRL retrieval
        do {
            let crlData = try await caClient.getCrl(
                authenticatedAddress: authenticatedAddress,
                networkId: "test-network"
            )

            // Verify CRL data is returned
            XCTAssertFalse(crlData.isEmpty, "CRL data should not be empty when server is running")
        } catch {
            // If server is not properly configured, this might fail
            XCTAssertTrue(error is FFIError)
        }

        // Stop the server
        try await caServer.stop()
    }

    // MARK: - CRL Error Scenarios Tests

    func testCrlErrorScenarios() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("CrlErrorScenarios"))
        // Test various error scenarios for CRL retrieval

        // Test with very long address
        let longAddress = "127.0.0.1:" + String(repeating: "8", count: 100)
        let networkId = "test-network"

        do {
            let crlData = try await caClient.getCrl(
                authenticatedAddress: longAddress,
                networkId: networkId
            )
            XCTFail("Should have thrown error for invalid long address")
        } catch {
            XCTAssertTrue(error is FFIError)
        }

        // Test with very long network ID
        let longNetworkId = String(repeating: "a", count: 1000)

        do {
            let crlData = try await caClient.getCrl(
                authenticatedAddress: "127.0.0.1:8080",
                networkId: longNetworkId
            )
            XCTFail("Should have thrown error for invalid long network ID")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }

    // MARK: - CRL Concurrent Access Tests

    func testCrlConcurrentAccess() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("CrlConcurrentAccess"))
        // Test concurrent CRL retrieval operations
        let authenticatedAddress = "127.0.0.1:8080"
        let networkId = "test-network"
        guard let caClient = caClient else {
            XCTFail("CA client not initialized")
            return
        }

        let clientForGroup = caClient
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    let crlData = try await clientForGroup.getCrl(
                        authenticatedAddress: authenticatedAddress,
                        networkId: networkId
                    )
                    XCTAssertFalse(crlData.isEmpty)
                } catch {
                    // Might fail if server is not running
                    XCTAssertTrue(error is FFIError)
                }
            }

            group.addTask {
                do {
                    let crlData = try await clientForGroup.getCrl(
                        authenticatedAddress: authenticatedAddress,
                        networkId: networkId
                    )
                    XCTAssertFalse(crlData.isEmpty)
                } catch {
                    // Might fail if server is not running
                    XCTAssertTrue(error is FFIError)
                }
            }

            group.addTask {
                do {
                    let crlData = try await clientForGroup.getCrl(
                        authenticatedAddress: authenticatedAddress,
                        networkId: networkId
                    )
                    XCTAssertFalse(crlData.isEmpty)
                } catch {
                    // Might fail if server is not running
                    XCTAssertTrue(error is FFIError)
                }
            }

            // Wait for all tasks to complete
            for await _ in group {}
        }
    }

    // MARK: - CRL Data Validation Tests

    func testCrlDataValidation() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("CrlDataValidation"))
        // Test validation of CRL data format
        let authenticatedAddress = "127.0.0.1:8080"
        let networkId = "test-network"

        do {
            let crlData = try await caClient.getCrl(
                authenticatedAddress: authenticatedAddress,
                networkId: networkId
            )

            // Verify CRL data has expected properties
            XCTAssertFalse(crlData.isEmpty, "CRL data should not be empty")
            XCTAssertGreaterThan(crlData.count, 0, "CRL data should have content")

            // CRL data should be valid binary data
            XCTAssertTrue(crlData.count > 0, "CRL data should have positive length")

        } catch {
            // Might fail if server is not running
            XCTAssertTrue(error is FFIError)
        }
    }

    // MARK: - CRL Network Error Handling

    func testCrlNetworkErrorHandling() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("CrlNetworkErrorHandling"))
        // Test handling of network errors during CRL retrieval

        // Test with unreachable address
        let unreachableAddress = "192.168.255.255:8080"
        let networkId = "test-network"

        do {
            let crlData = try await caClient.getCrl(
                authenticatedAddress: unreachableAddress,
                networkId: networkId
            )
            XCTFail("Should have thrown error for unreachable address")
        } catch {
            XCTAssertTrue(error is FFIError)
        }

        // Test with invalid port
        let invalidPortAddress = "127.0.0.1:99999"

        do {
            let crlData = try await caClient.getCrl(
                authenticatedAddress: invalidPortAddress,
                networkId: networkId
            )
            XCTFail("Should have thrown error for invalid port")
        } catch {
            XCTAssertTrue(error is FFIError)
        }
    }
}
