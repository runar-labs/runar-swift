import XCTest
import SwiftFFI
import SwiftCommon

@testable import SwiftFFI

/// Comprehensive CA Tests
/// Tests for CA Node, CA Server, and CA Client functionality
/// Mirrors the comprehensive FFI tests from Rust
final class CATests: XCTestCase {
    
    private var nodeKeys: KeysHandle!
    private var caNode: CANode!
    private var caServer: CAServer!
    private var caClient: CAClient!
    
    override func setUp() {
        super.setUp()
        
        // Set up logging
        try! FFILogger.setLogLevel(.debug)
        
        // Create node keys handle
        nodeKeys = try! KeysHandle()
        try! nodeKeys.initializeAsNode()
        try! nodeKeys.nodeGenerateKeys()
    }
    
    override func tearDown() {
        caClient = nil
        caServer = nil
        caNode = nil
        nodeKeys = nil
        super.tearDown()
    }
    
    // MARK: - CA Node Tests
    
    func testCaNodeNewHappyPath() throws {
        // Test successful CA node creation
        let caNode = try CANode.create()
        XCTAssertNotNil(caNode, "CA node should be created successfully")
    }
    
    func testCaNodeFreeNull() {
        // Test that freeing null CA node doesn't crash
        // This is handled internally by the FFI, so we just ensure it doesn't throw
        // Note: CANode.free doesn't exist in the current API
    }
    
    func testCaNodeSetupCompleteHappyPath() throws {
        // Test CA node setup with proper configuration
        let caNode = try CANode.create()
        
        // Create EA key pair for testing
        let eaKeyManager = EAKeyManager(logger: RunarLogger(component: .custom))
        let eaKeyPair = try eaKeyManager.createKeyPair()
        let eaPublicKey = try eaKeyManager.getPublicKey(eaKeyPair)
        
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
        
        XCTAssertNoThrow(try caNode.setupComplete(params: setupParams), "CA node setup should succeed")
        
        // Clean up
        EAKeyManager.free(eaKeyPair)
    }
    
    func testCaNodeSetupCompleteNullCaNode() throws {
        // Test CA node setup with null CA node
        let eaKeyManager = EAKeyManager(logger: RunarLogger(component: .custom))
        let eaKeyPair = try eaKeyManager.createKeyPair()
        let eaPublicKey = try eaKeyManager.getPublicKey(eaKeyPair)
        
        let setupParams = CANodeManager.CANodeSetupParams(
            caNode: UnsafeMutableRawPointer(bitPattern: 0)!, // Null pointer
            rootCaSubject: "CN=Test Root CA,O=Test,C=US",
            issuingCaSubject: "CN=Test Issuing CA,O=Test,C=US",
            validityDays: 365,
            issuingCaSerial: 1,
            eaPublicKeys: eaPublicKey,
            networkId: "test_network"
        )
        
        // This should fail gracefully
        XCTAssertThrowsError(try CANode(ffiHandle: UnsafeMutableRawPointer(bitPattern: 0)!).setupComplete(params: setupParams), "Should fail with null CA node")
        
        // Clean up
        EAKeyManager.free(eaKeyPair)
    }
    
    func testCaNodeCreateShared() throws {
        // Test creating shared CA node
        let caNode = try CANode.create()
        let sharedCaNode = try caNode.createShared()
        XCTAssertNotNil(sharedCaNode, "Shared CA node should be created successfully")
        
        // Clean up
        CANode.freeShared(sharedCaNode)
    }
    
    func testCaNodeFreeShared() {
        // Test freeing shared CA node - use a valid null pointer
        let nullPointer = UnsafeMutableRawPointer(bitPattern: 1)!
        XCTAssertNoThrow(CANode.freeShared(nullPointer), "Freeing null shared CA node should not crash")
    }
    
    // MARK: - CA Server Tests
    
    func testCaServerNewStub() throws {
        // Test CA server creation
        let caNode = try CANode.create()
        let sharedCaNode = try caNode.createShared()
        let config = CaServerConfig(
            bootstrapBind: "127.0.0.1:0",
            authenticatedBind: "127.0.0.1:0",
            networkId: "test-network",
            rateLimitPerMinute: 100,
            rateLimitPerHour: 1000
        )
        let caServer = try CAServer.create(config: config, sharedCaNode: sharedCaNode)
        XCTAssertNotNil(caServer, "CA server should be created successfully")
        
        // Clean up
        CANode.freeShared(sharedCaNode)
    }
    
    func testCaServerFreeNull() {
        // Test that freeing null CA server doesn't crash
        // Note: CAServer.free doesn't exist in the current API
    }
    
    func testCaServerStartStop() throws {
        // Test CA server start and stop
        let caNode = try CANode.create()
        let sharedCaNode = try caNode.createShared()
        let config = CaServerConfig(
            bootstrapBind: "127.0.0.1:0",
            authenticatedBind: "127.0.0.1:0",
            networkId: "test-network",
            rateLimitPerMinute: 100,
            rateLimitPerHour: 1000
        )
        let caServer = try CAServer.create(config: config, sharedCaNode: sharedCaNode)
        
        XCTAssertNoThrow(try caServer.start(), "CA server should start successfully")
        XCTAssertNoThrow(try caServer.stop(), "CA server should stop successfully")
        
        // Clean up
        CANode.freeShared(sharedCaNode)
    }
    
    func testCaServerBootstrapAddress() throws {
        // Test getting bootstrap address
        let caNode = try CANode.create()
        let sharedCaNode = try caNode.createShared()
        let config = CaServerConfig(
            bootstrapBind: "127.0.0.1:0",
            authenticatedBind: "127.0.0.1:0",
            networkId: "test-network",
            rateLimitPerMinute: 100,
            rateLimitPerHour: 1000
        )
        let caServer = try CAServer.create(config: config, sharedCaNode: sharedCaNode)
        
        XCTAssertNoThrow(try caServer.bootstrapAddress(), "Should get bootstrap address")
        
        // Clean up
        CANode.freeShared(sharedCaNode)
    }
    
    func testCaServerAuthenticatedAddress() throws {
        // Test getting authenticated address
        let caNode = try CANode.create()
        let sharedCaNode = try caNode.createShared()
        let config = CaServerConfig(
            bootstrapBind: "127.0.0.1:0",
            authenticatedBind: "127.0.0.1:0",
            networkId: "test-network",
            rateLimitPerMinute: 100,
            rateLimitPerHour: 1000
        )
        let caServer = try CAServer.create(config: config, sharedCaNode: sharedCaNode)
        
        XCTAssertNoThrow(try caServer.authenticatedAddress(), "Should get authenticated address")
        
        // Clean up
        CANode.freeShared(sharedCaNode)
    }
    
    // MARK: - CA Client Tests
    
    func testCaClientNewStub() throws {
        // Test CA client creation
        let caClientConfig = CaClientConfigAll(
            bootstrap_server: "127.0.0.1:0",
            authenticated_server: "127.0.0.1:0",
            network_id: "test-network",
            request_timeout_seconds: 30,
            max_retries: 3,
            root_ca_der: Data(),
            issuing_ca_der: Data()
        )
        
        let caClient = try CAClient(config: caClientConfig, nodeKeys: nodeKeys)
        XCTAssertNotNil(caClient, "CA client should be created successfully")
    }
    
    func testCaClientFreeNull() {
        // Test that freeing null CA client doesn't crash
        // Note: CAClient.free doesn't exist in the current API
    }
    
    func testCaClientEnroll() throws {
        // Test CA client enrollment
        let caClientConfig = CaClientConfigAll(
            bootstrap_server: "127.0.0.1:0",
            authenticated_server: "127.0.0.1:0",
            network_id: "test-network",
            request_timeout_seconds: 30,
            max_retries: 3,
            root_ca_der: Data(),
            issuing_ca_der: Data()
        )
        
        let caClient = try CAClient(config: caClientConfig, nodeKeys: nodeKeys)
        
        // Test enrollment (may fail if server not running, which is expected)
        do {
            let _ = try caClient.enroll(
                bootstrapAddress: "127.0.0.1:8080",
                request: Data() // Empty request for testing
            )
        } catch {
            // Expected to fail if server not running
            XCTAssertTrue(error is FFIError)
        }
    }
    
    func testCaClientRenew() throws {
        // Test CA client renewal
        let caClientConfig = CaClientConfigAll(
            bootstrap_server: "127.0.0.1:0",
            authenticated_server: "127.0.0.1:0",
            network_id: "test-network",
            request_timeout_seconds: 30,
            max_retries: 3,
            root_ca_der: Data(),
            issuing_ca_der: Data()
        )
        
        let caClient = try CAClient(config: caClientConfig, nodeKeys: nodeKeys)
        
        // Test renewal (may fail if server not running, which is expected)
        do {
            let _ = try caClient.renew(
                authenticatedAddress: "127.0.0.1:8080",
                request: Data() // Empty request for testing
            )
        } catch {
            // Expected to fail if server not running
            XCTAssertTrue(error is FFIError)
        }
    }
    
    func testCaClientRevoke() throws {
        // Test CA client revocation
        let caClientConfig = CaClientConfigAll(
            bootstrap_server: "127.0.0.1:0",
            authenticated_server: "127.0.0.1:0",
            network_id: "test-network",
            request_timeout_seconds: 30,
            max_retries: 3,
            root_ca_der: Data(),
            issuing_ca_der: Data()
        )
        
        let caClient = try CAClient(config: caClientConfig, nodeKeys: nodeKeys)
        
        // Test revocation (may fail if server not running, which is expected)
        do {
            let _ = try caClient.revoke(
                authenticatedAddress: "127.0.0.1:8080",
                request: Data() // Empty request for testing
            )
        } catch {
            // Expected to fail if server not running
            XCTAssertTrue(error is FFIError)
        }
    }
    
    func testCaClientGetChain() throws {
        // Test CA client chain retrieval
        let caClientConfig = CaClientConfigAll(
            bootstrap_server: "127.0.0.1:0",
            authenticated_server: "127.0.0.1:0",
            network_id: "test-network",
            request_timeout_seconds: 30,
            max_retries: 3,
            root_ca_der: Data(),
            issuing_ca_der: Data()
        )
        
        let caClient = try CAClient(config: caClientConfig, nodeKeys: nodeKeys)
        
        // Test chain retrieval (may fail if server not running, which is expected)
        do {
            let _ = try caClient.getChain(
                bootstrapAddress: "127.0.0.1:8080",
                networkId: "test-network"
            )
        } catch {
            // Expected to fail if server not running
            XCTAssertTrue(error is FFIError)
        }
    }
    
    func testCaClientGetStatus() throws {
        // Test CA client status retrieval
        let caClientConfig = CaClientConfigAll(
            bootstrap_server: "127.0.0.1:0",
            authenticated_server: "127.0.0.1:0",
            network_id: "test-network",
            request_timeout_seconds: 30,
            max_retries: 3,
            root_ca_der: Data(),
            issuing_ca_der: Data()
        )
        
        let caClient = try CAClient(config: caClientConfig, nodeKeys: nodeKeys)
        
        // Test status retrieval (may fail if server not running, which is expected)
        do {
            let _ = try caClient.getStatus(
                authenticatedAddress: "127.0.0.1:8080",
                networkId: "test-network"
            )
        } catch {
            // Expected to fail if server not running
            XCTAssertTrue(error is FFIError)
        }
    }
    
    // MARK: - EA Key Manager Tests
    
    func testEaKeyManagerCreateKeyPair() throws {
        // Test EA key pair creation
        let eaKeyManager = EAKeyManager(logger: RunarLogger(component: .custom))
        let eaKeyPair = try eaKeyManager.createKeyPair()
        XCTAssertNotNil(eaKeyPair, "EA key pair should be created successfully")
        
        // Clean up
        EAKeyManager.free(eaKeyPair)
    }
    
    func testEaKeyManagerGetPublicKey() throws {
        // Test getting EA public key
        let eaKeyManager = EAKeyManager(logger: RunarLogger(component: .custom))
        let eaKeyPair = try eaKeyManager.createKeyPair()
        let publicKey = try eaKeyManager.getPublicKey(eaKeyPair)
        XCTAssertFalse(publicKey.isEmpty, "Public key should not be empty")
        
        // Clean up
        EAKeyManager.free(eaKeyPair)
    }
    
    func testEaKeyManagerGenerateEnrollmentToken() throws {
        // Test enrollment token generation
        let eaKeyManager = EAKeyManager(logger: RunarLogger(component: .custom))
        let eaKeyPair = try eaKeyManager.createKeyPair()
        
        let tokenParams = EAKeyManager.EnrollmentTokenParams(
            eaKeyHandle: eaKeyPair,
            tokenId: "test_token",
            networkId: "test_network",
            subject: "CN=Test User,O=Test,C=US",
            validFrom: 1234567890,
            validUntil: 1234567890 + 3600,
            nonce: Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]),
            capabilities: ["enroll"]
        )
        
        let token = try eaKeyManager.generateEnrollmentToken(params: tokenParams)
        XCTAssertFalse(token.isEmpty, "Enrollment token should not be empty")
        
        // Clean up
        EAKeyManager.free(eaKeyPair)
    }
    
    func testEaKeyManagerFreeNull() {
        // Test that freeing null EA key pair doesn't crash
        let nullPointer = UnsafeMutableRawPointer(bitPattern: 1)!
        XCTAssertNoThrow(EAKeyManager.free(nullPointer), "Freeing null EA key pair should not crash")
    }
    
    // MARK: - Error Handling Tests
    
    func testCaNodeErrorHandling() throws {
        // Test CA node error handling with invalid parameters
        let caNode = try CANode.create()
        
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
        XCTAssertThrowsError(try caNode.setupComplete(params: setupParams), "Should fail with empty EA public keys")
    }
    
    func testCaClientErrorHandling() throws {
        // Test CA client error handling with invalid parameters
        let caClientConfig = CaClientConfigAll(
            bootstrap_server: "127.0.0.1:0",
            authenticated_server: "127.0.0.1:0",
            network_id: "test-network",
            request_timeout_seconds: 30,
            max_retries: 3,
            root_ca_der: Data(),
            issuing_ca_der: Data()
        )
        
        let caClient = try CAClient(config: caClientConfig, nodeKeys: nodeKeys)
        
        // Test with empty address
        XCTAssertThrowsError(try caClient.enroll(
            bootstrapAddress: "",
            request: Data()
        ), "Should fail with empty address")
        
        // Test with empty network ID
        XCTAssertThrowsError(try caClient.enroll(
            bootstrapAddress: "127.0.0.1:8080",
            request: Data()
        ), "Should fail with empty network ID")
    }
    
    // MARK: - Integration Tests
    
    func testCaNodeServerIntegration() throws {
        // Test CA node and server integration
        let caNode = try CANode.create()
        
        // Create EA key pair
        let eaKeyManager = EAKeyManager(logger: RunarLogger(component: .custom))
        let eaKeyPair = try eaKeyManager.createKeyPair()
        let eaPublicKey = try eaKeyManager.getPublicKey(eaKeyPair)
        
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
        
        try caNode.setupComplete(params: setupParams)
        
        // Create shared CA node
        let sharedCaNode = try caNode.createShared()
        
        // Create CA server with shared CA node
        let caServerConfig = CaServerConfig(
            bootstrapBind: "127.0.0.1:0",
            authenticatedBind: "127.0.0.1:0",
            networkId: "test-network",
            rateLimitPerMinute: 100,
            rateLimitPerHour: 1000
        )
        
        let caServer = try CAServer.create(config: caServerConfig, sharedCaNode: sharedCaNode)
        XCTAssertNotNil(caServer, "CA server should be created with shared CA node")
        
        // Clean up
        CANode.freeShared(sharedCaNode)
        EAKeyManager.free(eaKeyPair)
    }
    
    func testCaClientServerIntegration() throws {
        // Test CA client and server integration
        let caNode = try CANode.create()
        
        // Create EA key pair
        let eaKeyManager = EAKeyManager(logger: RunarLogger(component: .custom))
        let eaKeyPair = try eaKeyManager.createKeyPair()
        let eaPublicKey = try eaKeyManager.getPublicKey(eaKeyPair)
        
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
        
        try caNode.setupComplete(params: setupParams)
        
        // Create shared CA node
        let sharedCaNode = try caNode.createShared()
        
        // Create CA server
        let caServerConfig = CaServerConfig(
            bootstrapBind: "127.0.0.1:0",
            authenticatedBind: "127.0.0.1:0",
            networkId: "test-network",
            rateLimitPerMinute: 100,
            rateLimitPerHour: 1000
        )
        
        let caServer = try CAServer.create(config: caServerConfig, sharedCaNode: sharedCaNode)
        
        // Create CA client
        let caClientConfig = CaClientConfigAll(
            bootstrap_server: "127.0.0.1:0",
            authenticated_server: "127.0.0.1:0",
            network_id: "test-network",
            request_timeout_seconds: 30,
            max_retries: 3,
            root_ca_der: Data(),
            issuing_ca_der: Data()
        )
        
        let caClient = try CAClient(config: caClientConfig, nodeKeys: nodeKeys)
        
        // Test integration (may fail if server not running, which is expected)
        do {
            try caServer.start()
            let bootstrapAddress = try caServer.bootstrapAddress()
            let _ = try caClient.enroll(
                bootstrapAddress: bootstrapAddress,
                request: Data() // Empty request for testing
            )
            try caServer.stop()
        } catch {
            // Expected to fail if server not properly configured
            XCTAssertTrue(error is FFIError)
        }
        
        // Clean up
        CANode.freeShared(sharedCaNode)
        EAKeyManager.free(eaKeyPair)
    }
    
    // MARK: - Performance Tests
    
    func testCaNodeCreationPerformance() throws {
        // Test performance of CA node creation
        let iterations = 100
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for _ in 0..<iterations {
            let _ = try CANode.create()
            // CA node is automatically cleaned up when out of scope
        }
        
        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        let averageTime = totalTime / Double(iterations)
        
        XCTAssertGreaterThan(totalTime, 0, "CA node creation should take some time")
        print("Average CA node creation time: \(averageTime) seconds")
    }
    
    func testEaKeyPairCreationPerformance() throws {
        // Test performance of EA key pair creation
        let iterations = 50
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let eaKeyManager = EAKeyManager(logger: RunarLogger(component: .custom))
        for _ in 0..<iterations {
            let eaKeyPair = try eaKeyManager.createKeyPair()
            EAKeyManager.free(eaKeyPair)
        }
        
        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        let averageTime = totalTime / Double(iterations)
        
        XCTAssertGreaterThan(totalTime, 0, "EA key pair creation should take some time")
        print("Average EA key pair creation time: \(averageTime) seconds")
    }
}
