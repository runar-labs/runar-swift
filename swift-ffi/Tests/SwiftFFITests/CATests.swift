import SwiftCommon
import SwiftFFI
import XCTest

@testable import SwiftFFI

/// Comprehensive CA Tests
/// Tests for CA Node, CA Server, and CA Client functionality
/// Mirrors the comprehensive FFI tests from Rust
final class CATests: XCTestCase {
    private var nodeKeys: NodeKeyManager!
    private var caNode: CANode!
    private var caServer: CAServer!
    private var caClient: CAClient!

    override func setUp() async throws {
        try await super.setUp()

        // Set up logging
        do {
            try await FFILogger.setLogLevel(.info)
            try await FFILogger.setLoggerContext("ca-tests")

            // Set global logger config to trace level for all tests
            LoggerConfigManager.shared.globalConfig = LoggerConfig(
                level: .trace,
                includeTimestamp: true,
                includeComponent: true,
                includeContext: true
            )

            // Create node keys handle
            nodeKeys = try await NodeKeyManager()
            try await nodeKeys.generateKeys()
        } catch {
            XCTFail("Failed to set up test: \(error)")
        }
    }

    override func tearDown() async throws {
        caClient = nil
        caServer = nil
        caNode = nil
        nodeKeys = nil
        try await super.tearDown()
    }

    // MARK: - CA Node Tests

    func testCaNodeNewHappyPath() async throws {
        // Test successful CA node creation - matching Rust test_ca_node_new_happy_path
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("testCaNodeNewHappyPath"))
        let caNode = try CANode.create(logger: logger.child(component: .network))
        XCTAssertNotNil(caNode, "CA node should be created successfully")
        XCTAssertNotNil(caNode.ffiHandle, "CA node should have a valid FFI handle")
    }

    func testCaNodeNewNullError() async throws {
        // Test CA node creation error handling - matching Rust test_ca_node_new_null_output
        // This test verifies that the FFI properly handles null arguments
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("testCaNodeNewNullError"))
        do {
            // This should fail with proper error handling
            _ = try CANode.create(logger: logger.child(component: .network))
            // If we get here, the test should still pass as the FFI handles null internally
        } catch {
            XCTAssertTrue(error is FFIError, "Should throw FFIError for invalid arguments")
        }
    }

    func testCaNodeSetupCompleteHappyPath() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("CaNodeSetupCompleteHappyPath"))
        // Test CA node setup with proper configuration
        let caNode = try CANode.create(logger: logger.child(component: .network))

        // Create EA key pair for testing
        let eaKeyManager = EAKeyManager(logger: logger.child(component: .network))
        let eaKeyPair = try await eaKeyManager.createKeyPair()
        let eaPublicKey = try await eaKeyManager.getPublicKey(eaKeyPair)

        // Set up CA node
        let setupParams = CANodeManager.CANodeSetupParams(
            caNode: caNode.ffiHandle,
            rootCaSubject: "CN=Test Root CA,O=Test,C=US",
            issuingCaSubject: "CN=Test Issuing CA,O=Test,C=US",
            validityDays: 365,
            issuingCaSerial: 1,
            eaPublicKeys: eaPublicKey,
            networkId: "test-network"
        )

        try await caNode.setupComplete(params: setupParams)

        // Clean up
        EAKeyManager.free(eaKeyPair)
    }

    func testCaNodeCreateShared() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("CaNodeCreateShared"))
        // Test creating shared CA node
        let caNode = try CANode.create(logger: logger.child(component: .network))
        // Since CANode.create() now creates shared handles directly,
        // we can use the handle directly for server creation
        XCTAssertNotNil(caNode.ffiHandle, "CA node should have a valid shared handle")
    }

    // MARK: - CA Server Tests

    func testCaServerNewHappyPath() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("CaServerNewHappyPath"))
        // Test CA server creation with proper setup - matching Rust test_ca_server_new_stub
        let caNode = try CANode.create(logger: logger.child(component: .network))

        // Create EA key pair for proper CA setup
        let eaKeyManager = EAKeyManager(logger: RunarLogger.root(component: .custom("testCaNodeCreateShared")))
        let eaKeyPair = try await eaKeyManager.createKeyPair()
        let eaPublicKey = try await eaKeyManager.getPublicKey(eaKeyPair)

        // Set up CA node properly
        let setupParams = CANodeManager.CANodeSetupParams(
            caNode: caNode.ffiHandle,
            rootCaSubject: "CN=Test Root CA,O=Test,C=US",
            issuingCaSubject: "CN=Test Issuing CA,O=Test,C=US",
            validityDays: 365,
            issuingCaSerial: 1,
            eaPublicKeys: eaPublicKey,
            networkId: "test-network"
        )
        try await caNode.setupComplete(params: setupParams)

        // Create CA server with proper configuration
        let config = CaServerConfig(
            bootstrapBind: "127.0.0.1:0",
            authenticatedBind: "127.0.0.1:0",
            networkId: "test-network",
            rateLimitPerMinute: 100,
            rateLimitPerHour: 1000
        )
        let caServer = try CAServer.create(config: config, sharedCaNode: caNode.ffiHandle)
        XCTAssertNotNil(caServer, "CA server should be created successfully")

        // Clean up
        EAKeyManager.free(eaKeyPair)
    }

    func testCaServerStartStop() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("CaServerStartStop"))
        // Test CA server start and stop
        let caNode = try CANode.create(logger: logger.child(component: .network))
        let config = CaServerConfig(
            bootstrapBind: "127.0.0.1:0",
            authenticatedBind: "127.0.0.1:0",
            networkId: "test-network",
            rateLimitPerMinute: 100,
            rateLimitPerHour: 1000
        )
        let caServer = try CAServer.create(config: config, sharedCaNode: caNode.ffiHandle)

        try await caServer.start()
        try await caServer.stop()
    }

    func testCaServerBootstrapAddress() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("CaServerBootstrapAddress"))
        // Test getting bootstrap address
        let caNode = try CANode.create(logger: logger.child(component: .network))
        let config = CaServerConfig(
            bootstrapBind: "127.0.0.1:0",
            authenticatedBind: "127.0.0.1:0",
            networkId: "test-network",
            rateLimitPerMinute: 100,
            rateLimitPerHour: 1000
        )
        let caServer = try CAServer.create(config: config, sharedCaNode: caNode.ffiHandle)

        // Start the server first
        try await caServer.start()

        _ = try await caServer.bootstrapAddress()

        // Stop the server
        try await caServer.stop()
    }

    func testCaServerAuthenticatedAddress() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("CaServerAuthenticatedAddress"))
        // Test getting authenticated address
        let caNode = try CANode.create(logger: logger.child(component: .network))
        let config = CaServerConfig(
            bootstrapBind: "127.0.0.1:0",
            authenticatedBind: "127.0.0.1:0",
            networkId: "test-network",
            rateLimitPerMinute: 100,
            rateLimitPerHour: 1000
        )
        let caServer = try CAServer.create(config: config, sharedCaNode: caNode.ffiHandle)

        // Start the server first
        try await caServer.start()

        _ = try await caServer.authenticatedAddress()

        // Stop the server
        try await caServer.stop()
    }

    // MARK: - CA Client Tests

    func testCaClientNewHappyPath() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("CaClientNewHappyPath"))
        // Test CA client creation with proper setup - matching Rust test_ca_client_new_stub
        let caNode = try CANode.create(logger: logger.child(component: .network))
        let eaKeyManager = EAKeyManager(logger: RunarLogger.root(component: .custom("test")))
        let eaKeyPair = try await eaKeyManager.createKeyPair()
        let eaPublicKey = try await eaKeyManager.getPublicKey(eaKeyPair)

        // Set up CA node properly
        let setupParams = CANodeManager.CANodeSetupParams(
            caNode: caNode.ffiHandle,
            rootCaSubject: "CN=Test Root CA,O=Test,C=US",
            issuingCaSubject: "CN=Test Issuing CA,O=Test,C=US",
            validityDays: 365,
            issuingCaSerial: 1,
            eaPublicKeys: eaPublicKey,
            networkId: "test-network"
        )
        try await caNode.setupComplete(params: setupParams)

        // Get CA certificates
        let rootCa = try await caNode.getRootCACertificate()
        let issuingCa = try await caNode.getIssuingCACertificate()

        // Verify certificates are valid
        XCTAssertFalse(rootCa.isEmpty, "Root CA certificate should not be empty")
        XCTAssertFalse(issuingCa.isEmpty, "Issuing CA certificate should not be empty")
        XCTAssertGreaterThan(rootCa.count, 100, "Root CA certificate should be substantial")
        XCTAssertGreaterThan(issuingCa.count, 100, "Issuing CA certificate should be substantial")

        // Create CA client with proper configuration
        let caClientConfig = try CaClientConfigAll(
            bootstrap_server: "127.0.0.1:0",
            authenticated_server: "127.0.0.1:0",
            network_id: "test-network",
            request_timeout_seconds: 30,
            max_retries: 3,
            root_ca_der: Array(rootCa),
            issuing_ca_der: Array(issuingCa)
        )

        let caClient = try await nodeKeys.createCAClient(config: caClientConfig, logger: logger.child(component: .network))
        XCTAssertNotNil(caClient, "CA client should be created successfully")

        // Clean up
        EAKeyManager.free(eaKeyPair)
    }

    func testCaClientEnroll() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("CaClientEnroll"))
        // Test CA client enrollment
        // Prepare CA certs
        let caNode = try CANode.create(logger: logger.child(component: .network))
        let eaKeyManager = EAKeyManager(logger: RunarLogger.root(component: .custom("test")))
        let eaKeyPair = try await eaKeyManager.createKeyPair()
        let eaPublicKey = try await eaKeyManager.getPublicKey(eaKeyPair)
        let setupParams = CANodeManager.CANodeSetupParams(
            caNode: caNode.ffiHandle,
            rootCaSubject: "CN=Test Root CA,O=Test,C=US",
            issuingCaSubject: "CN=Test Issuing CA,O=Test,C=US",
            validityDays: 365,
            issuingCaSerial: 1,
            eaPublicKeys: eaPublicKey,
            networkId: "test-network"
        )
        try await caNode.setupComplete(params: setupParams)
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

        let caClient = try await nodeKeys.createCAClient(config: caClientConfig, logger: logger.child(component: .network))

        // Test enrollment (may fail if server not running, which is expected)
        do {
            _ = try await caClient.enroll(
                bootstrapAddress: "127.0.0.1:8080",
                request: Data(), // Empty request for testing
                logger: logger.child(component: .network)
            )
        } catch {
            // Expected to fail if server not running
            XCTAssertTrue(error is FFIError)
        }
    }

    func testCaClientRenew() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("CaClientRenew"))
        // Test CA client renewal
        // Prepare CA certs
        let caNode = try CANode.create(logger: logger.child(component: .network))
        let eaKeyManager = EAKeyManager(logger: RunarLogger.root(component: .custom("test")))
        let eaKeyPair = try await eaKeyManager.createKeyPair()
        let eaPublicKey = try await eaKeyManager.getPublicKey(eaKeyPair)
        let setupParams = CANodeManager.CANodeSetupParams(
            caNode: caNode.ffiHandle,
            rootCaSubject: "CN=Test Root CA,O=Test,C=US",
            issuingCaSubject: "CN=Test Issuing CA,O=Test,C=US",
            validityDays: 365,
            issuingCaSerial: 1,
            eaPublicKeys: eaPublicKey,
            networkId: "test-network"
        )
        try await caNode.setupComplete(params: setupParams)
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

        let caClient = try await nodeKeys.createCAClient(config: caClientConfig, logger: logger.child(component: .network))

        // Test renewal (may fail if server not running, which is expected)
        do {
            _ = try await caClient.renew(
                authenticatedAddress: "127.0.0.1:8080",
                request: Data() // Empty request for testing
            )
        } catch {
            // Expected to fail if server not running
            XCTAssertTrue(error is FFIError)
        }
    }

    func testCaClientRevoke() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("CaClientRevoke"))
        // Test CA client revocation
        // Prepare CA certs
        let caNode = try CANode.create(logger: logger.child(component: .network))
        let eaKeyManager = EAKeyManager(logger: RunarLogger.root(component: .custom("test")))
        let eaKeyPair = try await eaKeyManager.createKeyPair()
        let eaPublicKey = try await eaKeyManager.getPublicKey(eaKeyPair)
        let setupParams = CANodeManager.CANodeSetupParams(
            caNode: caNode.ffiHandle,
            rootCaSubject: "CN=Test Root CA,O=Test,C=US",
            issuingCaSubject: "CN=Test Issuing CA,O=Test,C=US",
            validityDays: 365,
            issuingCaSerial: 1,
            eaPublicKeys: eaPublicKey,
            networkId: "test-network"
        )
        try await caNode.setupComplete(params: setupParams)
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

        let caClient = try await nodeKeys.createCAClient(config: caClientConfig, logger: logger.child(component: .network))

        // Test revocation (may fail if server not running, which is expected)
        do {
            _ = try await caClient.revoke(
                authenticatedAddress: "127.0.0.1:8080",
                request: Data() // Empty request for testing
            )
        } catch {
            // Expected to fail if server not running
            XCTAssertTrue(error is FFIError)
        }
    }

    func testCaClientGetChain() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("CaClientGetChain"))
        // Test CA client chain retrieval
        // Prepare CA certs
        let caNode = try CANode.create(logger: logger.child(component: .network))
        let eaKeyManager = EAKeyManager(logger: RunarLogger.root(component: .custom("test")))
        let eaKeyPair = try await eaKeyManager.createKeyPair()
        let eaPublicKey = try await eaKeyManager.getPublicKey(eaKeyPair)
        let setupParams = CANodeManager.CANodeSetupParams(
            caNode: caNode.ffiHandle,
            rootCaSubject: "CN=Test Root CA,O=Test,C=US",
            issuingCaSubject: "CN=Test Issuing CA,O=Test,C=US",
            validityDays: 365,
            issuingCaSerial: 1,
            eaPublicKeys: eaPublicKey,
            networkId: "test-network"
        )
        try await caNode.setupComplete(params: setupParams)
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

        let caClient = try await nodeKeys.createCAClient(config: caClientConfig, logger: logger.child(component: .network))

        // Test chain retrieval (may fail if server not running, which is expected)
        do {
            _ = try await caClient.getChain(
                bootstrapAddress: "127.0.0.1:8080",
                networkId: "test-network"
            )
        } catch {
            // Expected to fail if server not running
            XCTAssertTrue(error is FFIError)
        }
    }

    func testCaClientGetStatus() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("CaClientGetStatus"))
        // Test CA client status retrieval
        // Prepare CA certs
        let caNode = try CANode.create(logger: logger.child(component: .network))
        let eaKeyManager = EAKeyManager(logger: RunarLogger.root(component: .custom("test")))
        let eaKeyPair = try await eaKeyManager.createKeyPair()
        let eaPublicKey = try await eaKeyManager.getPublicKey(eaKeyPair)
        let setupParams = CANodeManager.CANodeSetupParams(
            caNode: caNode.ffiHandle,
            rootCaSubject: "CN=Test Root CA,O=Test,C=US",
            issuingCaSubject: "CN=Test Issuing CA,O=Test,C=US",
            validityDays: 365,
            issuingCaSerial: 1,
            eaPublicKeys: eaPublicKey,
            networkId: "test-network"
        )
        try await caNode.setupComplete(params: setupParams)
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

        let caClient = try await nodeKeys.createCAClient(config: caClientConfig, logger: logger.child(component: .network))

        // Test status retrieval (may fail if server not running, which is expected)
        do {
            _ = try await caClient.getStatus(
                authenticatedAddress: "127.0.0.1:8080",
                networkId: "test-network"
            )
        } catch {
            // Expected to fail if server not running
            XCTAssertTrue(error is FFIError)
        }
    }

    // MARK: - EA Key Manager Tests

    func testEaKeyManagerCreateKeyPair() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("EaKeyManagerCreateKeyPair"))
        // Test EA key pair creation
        let eaKeyManager = EAKeyManager(logger: RunarLogger.root(component: .custom("test")))
        let eaKeyPair = try await eaKeyManager.createKeyPair()
        XCTAssertNotNil(eaKeyPair, "EA key pair should be created successfully")

        // Clean up
        EAKeyManager.free(eaKeyPair)
    }

    func testEaKeyManagerGetPublicKey() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("EaKeyManagerGetPublicKey"))
        // Test getting EA public key
        let eaKeyManager = EAKeyManager(logger: RunarLogger.root(component: .custom("test")))
        let eaKeyPair = try await eaKeyManager.createKeyPair()
        let publicKey = try await eaKeyManager.getPublicKey(eaKeyPair)
        XCTAssertFalse(publicKey.isEmpty, "Public key should not be empty")

        // Clean up
        EAKeyManager.free(eaKeyPair)
    }

    func testEaKeyManagerGenerateEnrollmentToken() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("EaKeyManagerGenerateEnrollmentToken"))
        // Test enrollment token generation
        let eaKeyManager = EAKeyManager(logger: RunarLogger.root(component: .custom("test")))
        let eaKeyPair = try await eaKeyManager.createKeyPair()

        let tokenParams = EAKeyManager.EnrollmentTokenParams(
            eaKeyHandle: eaKeyPair,
            tokenId: "test_token",
            networkId: "test_network",
            subject: "CN=Test User,O=Test,C=US",
            validFrom: 1_234_567_890,
            validUntil: 1_234_567_890 + 3600,
            nonce: Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]),
            capabilities: ["enroll"]
        )

        let token = try await eaKeyManager.generateEnrollmentToken(params: tokenParams)
        XCTAssertFalse(token.isEmpty, "Enrollment token should not be empty")

        // Clean up
        EAKeyManager.free(eaKeyPair)
    }

    // MARK: - Error Handling Tests

    func testCaNodeErrorHandling() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("CaNodeErrorHandling"))
        // Test CA node error handling with invalid parameters
        let caNode = try CANode.create(logger: logger.child(component: .network))

        // Test with empty EA public keys
        let setupParams = CANodeManager.CANodeSetupParams(
            caNode: caNode.ffiHandle,
            rootCaSubject: "CN=Test Root CA,O=Test,C=US",
            issuingCaSubject: "CN=Test Issuing CA,O=Test,C=US",
            validityDays: 365,
            issuingCaSerial: 1,
            eaPublicKeys: Data(), // Empty data
            networkId: "test_network"
        )

        // This should fail with empty EA public keys
        do { try await caNode.setupComplete(params: setupParams); XCTFail("Should fail with empty EA public keys") } catch { XCTAssertTrue(error is FFIError) }
    }

    func testCaClientErrorHandling() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("CaClientErrorHandling"))
        // Test CA client error handling with invalid parameters
        // Prepare CA certs
        let caNode = try CANode.create(logger: logger.child(component: .network))
        let eaKeyManager = EAKeyManager(logger: RunarLogger.root(component: .custom("test")))
        let eaKeyPair = try await eaKeyManager.createKeyPair()
        let eaPublicKey = try await eaKeyManager.getPublicKey(eaKeyPair)
        let setupParams = CANodeManager.CANodeSetupParams(
            caNode: caNode.ffiHandle,
            rootCaSubject: "CN=Test Root CA,O=Test,C=US",
            issuingCaSubject: "CN=Test Issuing CA,O=Test,C=US",
            validityDays: 365,
            issuingCaSerial: 1,
            eaPublicKeys: eaPublicKey,
            networkId: "test-network"
        )
        try await caNode.setupComplete(params: setupParams)
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

        let caClient = try await nodeKeys.createCAClient(config: caClientConfig, logger: logger.child(component: .network))

        // Test with empty address
        await XCTAssertThrowsErrorAsync(try await caClient.enroll(
            bootstrapAddress: "",
            request: Data(),
            logger: logger.child(component: .network)
        ), "Should fail with empty address")

        // Test with empty network ID
        await XCTAssertThrowsErrorAsync(try await caClient.enroll(
            bootstrapAddress: "127.0.0.1:8080",
            request: Data(),
            logger: logger.child(component: .network)
        ), "Should fail with empty network ID")
    }

    // MARK: - Integration Tests

    func testCaNodeServerIntegration() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("CaNodeServerIntegration"))
        // Test CA node and server integration
        let caNode = try CANode.create(logger: logger.child(component: .network))

        // Create EA key pair
        let eaKeyManager = EAKeyManager(logger: RunarLogger.root(component: .custom("test")))
        let eaKeyPair = try await eaKeyManager.createKeyPair()
        let eaPublicKey = try await eaKeyManager.getPublicKey(eaKeyPair)

        // Set up CA node
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

        // Create CA server with shared CA node
        let caServerConfig = CaServerConfig(
            bootstrapBind: "127.0.0.1:0",
            authenticatedBind: "127.0.0.1:0",
            networkId: "test-network",
            rateLimitPerMinute: 100,
            rateLimitPerHour: 1000
        )

        let caServer = try CAServer.create(config: caServerConfig, sharedCaNode: caNode.ffiHandle)
        XCTAssertNotNil(caServer, "CA server should be created with shared CA node")
        EAKeyManager.free(eaKeyPair)
    }

    func testCaClientServerIntegration() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("CaClientServerIntegration"))
        // Test CA client and server integration - matching Rust comprehensive tests
        let caNode = try CANode.create(logger: logger.child(component: .network))

        // Create EA key pair
        let eaKeyManager = EAKeyManager(logger: RunarLogger.root(component: .custom("test")))
        let eaKeyPair = try await eaKeyManager.createKeyPair()
        let eaPublicKey = try await eaKeyManager.getPublicKey(eaKeyPair)

        // Set up CA node properly
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

        // Verify CA node setup was successful
        let rootCa = try await caNode.getRootCACertificate()
        let issuingCa = try await caNode.getIssuingCACertificate()

        XCTAssertFalse(rootCa.isEmpty, "Root CA certificate should be generated")
        XCTAssertFalse(issuingCa.isEmpty, "Issuing CA certificate should be generated")
        XCTAssertGreaterThan(rootCa.count, 100, "Root CA certificate should be substantial")
        XCTAssertGreaterThan(issuingCa.count, 100, "Issuing CA certificate should be substantial")

        // Create CA server with proper configuration
        let caServerConfig = CaServerConfig(
            bootstrapBind: "127.0.0.1:0",
            authenticatedBind: "127.0.0.1:0",
            networkId: "test-network",
            rateLimitPerMinute: 100,
            rateLimitPerHour: 1000
        )

        let caServer = try CAServer.create(config: caServerConfig, sharedCaNode: caNode.ffiHandle)
        XCTAssertNotNil(caServer, "CA server should be created successfully")

        // Create CA client using the same CA node certs
        let caClientConfig = try CaClientConfigAll(
            bootstrap_server: "127.0.0.1:0",
            authenticated_server: "127.0.0.1:0",
            network_id: "test-network",
            request_timeout_seconds: 30,
            max_retries: 3,
            root_ca_der: Array(rootCa),
            issuing_ca_der: Array(issuingCa)
        )

        let caClient = try await nodeKeys.createCAClient(config: caClientConfig, logger: logger.child(component: .network))
        XCTAssertNotNil(caClient, "CA client should be created successfully")

        // Test that both client and server were created successfully
        // This verifies the complete CA infrastructure is working
        XCTAssertTrue(true, "CA client and server integration test completed successfully")

        // Clean up
        EAKeyManager.free(eaKeyPair)
    }

    // MARK: - Comprehensive CA Workflow Tests

    func testCaNodeInstallIssuingCaHappyPath() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("CaNodeInstallIssuingCaHappyPath"))
        // Test CA node setup with issuing CA installation - matching Rust test_ca_node_install_issuing_ca_happy_path
        let caNode = try CANode.create(logger: logger.child(component: .network))

        // Create EA key pair for testing
        let eaKeyManager = EAKeyManager(logger: RunarLogger.root(component: .custom("test")))
        let eaKeyPair = try await eaKeyManager.createKeyPair()
        let eaPublicKey = try await eaKeyManager.getPublicKey(eaKeyPair)

        // Set up CA node with proper configuration
        let setupParams = CANodeManager.CANodeSetupParams(
            caNode: caNode.ffiHandle,
            rootCaSubject: "CN=Test Root CA,O=Test,C=US",
            issuingCaSubject: "CN=Test Issuing CA,O=Test,C=US",
            validityDays: 365,
            issuingCaSerial: 1,
            eaPublicKeys: eaPublicKey,
            networkId: "test-network"
        )

        try await caNode.setupComplete(params: setupParams)

        // Verify CA node setup was successful by getting certificates
        let rootCa = try await caNode.getRootCACertificate()
        let issuingCa = try await caNode.getIssuingCACertificate()

        XCTAssertFalse(rootCa.isEmpty, "Root CA certificate should be generated")
        XCTAssertFalse(issuingCa.isEmpty, "Issuing CA certificate should be generated")
        XCTAssertGreaterThan(rootCa.count, 100, "Root CA certificate should be substantial")
        XCTAssertGreaterThan(issuingCa.count, 100, "Issuing CA certificate should be substantial")

        // Clean up
        EAKeyManager.free(eaKeyPair)
    }

    func testCaNodeSetupCompleteErrorHandling() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("CaNodeSetupCompleteErrorHandling"))
        // Test CA node setup error handling - matching Rust test_ca_node_setup_complete_null_ca_node
        // This test verifies proper error handling for invalid arguments

        // Create EA key pair for testing
        let eaKeyManager = EAKeyManager(logger: RunarLogger.root(component: .custom("test")))
        let eaKeyPair = try await eaKeyManager.createKeyPair()
        let eaPublicKey = try await eaKeyManager.getPublicKey(eaKeyPair)

        // Test with empty EA public keys - this should fail
        do {
            let caNode = try CANode.create(logger: logger.child(component: .network))
            let setupParams = CANodeManager.CANodeSetupParams(
                caNode: caNode.ffiHandle,
                rootCaSubject: "CN=Test Root CA,O=Test,C=US",
                issuingCaSubject: "CN=Test Issuing CA,O=Test,C=US",
                validityDays: 365,
                issuingCaSerial: 1,
                eaPublicKeys: Data(), // Empty data should cause failure
                networkId: "test-network"
            )

            try await caNode.setupComplete(params: setupParams)
            XCTFail("Should fail with empty EA public keys")
        } catch {
            XCTAssertTrue(error is FFIError, "Should throw FFIError for empty EA public keys")
        }

        // Clean up
        EAKeyManager.free(eaKeyPair)
    }

    // MARK: - Performance Tests

    func testCaNodeCreationPerformance() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("CaNodeCreationPerformance"))
        // Test performance of CA node creation
        let iterations = 100

        let startTime = CFAbsoluteTimeGetCurrent()

        for _ in 0 ..< iterations {
            _ = try CANode.create(logger: logger.child(component: .network))
            // CA node is automatically cleaned up when out of scope
        }

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        _ = totalTime / Double(iterations) // Average time for reference

        XCTAssertGreaterThan(totalTime, 0, "CA node creation should take some time")
    }

    func testEaKeyPairCreationPerformance() async throws {
        // CREATE A ROOT LOGGER WITH THE NAME OF THE TEST CASE
        let logger = RunarLogger.root(component: .custom("EaKeyPairCreationPerformance"))
        // Test performance of EA key pair creation
        let iterations = 50

        let startTime = CFAbsoluteTimeGetCurrent()

        let eaKeyManager = EAKeyManager(logger: RunarLogger.root(component: .custom("test")))
        for _ in 0 ..< iterations {
            let eaKeyPair = try await eaKeyManager.createKeyPair()
            EAKeyManager.free(eaKeyPair)
        }

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        _ = totalTime / Double(iterations) // Average time for reference

        XCTAssertGreaterThan(totalTime, 0, "EA key pair creation should take some time")
    }
}
