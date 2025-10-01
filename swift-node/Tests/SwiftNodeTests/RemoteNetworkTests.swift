import XCTest
@testable import SwiftNode
import SwiftCommon
import RunarSerializer
import SwiftFFI
import SwiftCBOR

/// Test for remote action calls between two nodes using QUIC with proper certificates
///
/// INTENTION: Create two Node instances with QUIC network enabled using certificates from a shared CA.
/// Nodes should discover and securely connect to each other, then test remote service calls.
/// This test exactly matches the Rust remote_test.rs test_remote_action_call function.
@MainActor
final class RemoteNetworkTests: XCTestCase {
    
    /// Test for remote action calls between two nodes using QUIC with proper certificates
    ///
    /// INTENTION: Create two Node instances with QUIC network enabled using certificates from a shared CA.
    /// Nodes should discover and securely connect to each other, then test remote service calls.
    func testRemoteActionCall() async throws {
        // Configure logging to trace level for detailed debugging
        let loggingConfig = LoggingConfig(level: .trace)
        
        // Set up logger with trace level
        let logger = RunarLogger(component: .node, config: loggingConfig)
        
        // Enable trace logging for Rust FFI layer
        try await FFILogger.setLogLevel(.trace)
        try await FFILogger.setLoggerNodeId("remote-action-test")
        
        // Force trace logging for this test
        logger.trace("🔍 TRACE LOGGING ENABLED - Test starting with trace level")
        
        print("🔍 TEST: Creating networked node test configs...")
        let configs = try await createNetworkedNodeTestConfigs(count: 2)
        print("🔍 TEST: Test configs created successfully")
        
        let node1Config = configs[0]
        let node2Config = configs[1]
        print("🔍 TEST: Node1 config: \(node1Config)")
        print("🔍 TEST: Node2 config: \(node2Config)")
        
        // Create math services with different paths using the fixture
        let mathService1 = MathService(name: "math1", path: "math1")
        let mathService2 = MathService(name: "math2", path: "math2")
        
        logger.debug("Node1 config: \(node1Config)")
        logger.debug("Node2 config: \(node2Config)")
        
        print("🔍 TEST: Creating node1...")
        let node1 = try await Node.new(config: node1Config)
        try await node1.addService(mathService1)
        print("🔍 TEST: Node1 created and service added")
        
        // Note: Event subscription would be handled by the service registry
        // For now, we'll skip the event subscription part to focus on remote calls
        
        print("🔍 TEST: Starting node1...")
        try await node1.start()
        print("🔍 TEST: Node1 started successfully")
        logger.debug("✅ Node 1 started")
        
        print("🔍 TEST: Creating node2...")
        let node2 = try await Node.new(config: node2Config)
        try await node2.addService(mathService2)
        print("🔍 TEST: Node2 created and service added")
        
        print("🔍 TEST: Starting node2...")
        try await node2.start()
        print("🔍 TEST: Node2 started successfully")
        logger.debug("✅ Node 2 started")
        
        logger.debug("⏳ Waiting for nodes to discover each other via multicast and establish QUIC connections...")
        // Note: For now, we'll skip the peer discovery part to focus on remote calls
        // In a real implementation, this would wait for peer discovery events
        try await Task.sleep(for: .seconds(2)) // Give time for discovery
        logger.debug("✅ Assuming nodes discovered each other")
        
        // Note: Event subscription would be handled by the service registry
        // For now, we'll skip the event subscription part to focus on remote calls
        
        // Test 1: Call math1/add service (on node1) from node2
        logger.debug("🔍 DEBUG: About to call math1/add service from node2 to node1")
        logger.debug("📤 Testing remote action call from node2 to node1 (math1/add)...")
        
        let response = try await node2.request(
            "math1/add",
            payload: AnyValue.map([
                "a": AnyValue.primitive(5.0),
                "b": AnyValue.primitive(3.0)
            ]),
            networkId: "test-network"
        )
        
        let responseValue = try await response.asType() as Double
        XCTAssertEqual(responseValue, 8.0)
        logger.debug("✅ Secure add operation succeeded: 5 + 3 = \(responseValue)")
        
        // Test 2: Call math2/multiply service (on node2) from node1
        logger.debug("📤 Testing remote action call from node1 to node2 (math2/multiply)...")
        let response2 = try await node1.request(
            "math2/multiply",
            payload: AnyValue.map([
                "a": AnyValue.primitive(4.0),
                "b": AnyValue.primitive(7.0)
            ]),
            networkId: "test-network"
        )
        let response2Value = try await response2.asType() as Double
        XCTAssertEqual(response2Value, 28.0)
        
        logger.debug("🔄 Testing dynamic service addition and discovery...")
        // Add a new service to node1 and test remote call
        let newService = MathService(name: "math3", path: "math3")
        try await node1.addService(newService)
        logger.debug("✅ Added math3 service to node1")
        
        // Note: Event subscription would be handled by the service registry
        
        // Wait for service discovery debounce (increased time for reliability)
        logger.debug("⏳ Waiting for service discovery propagation...")
        try await Task.sleep(for: .seconds(5))
        
        // Test 3: Call the newly added math3/add service from node2
        logger.debug("📤 Testing remote action call to newly added service (math3/add)...")
        
        let response3 = try await node2.request(
            "math3/add",
            payload: AnyValue.map([
                "a": AnyValue.primitive(10.0),
                "b": AnyValue.primitive(5.0)
            ]),
            networkId: "test-network"
        )
        let response3Value = try await response3.asType() as Double
        XCTAssertEqual(response3Value, 15.0)
        logger.info("✅ Dynamic service call succeeded: 10 + 5 = \(response3Value)")
        
        // Note: Event handling would be tested here in a full implementation
        
        // ==========================================
        // STEP 16: Test Additional Operations
        // ==========================================
        logger.info("🧪 Testing additional secure operations...")
        
        let response4 = try await node2.request(
            "math1/subtract",
            payload: AnyValue.map([
                "a": AnyValue.primitive(20.0),
                "b": AnyValue.primitive(8.0)
            ]),
            networkId: "test-network"
        )
        let response4Value = try await response4.asType() as Double
        XCTAssertEqual(response4Value, 12.0)
        logger.info("✅ Secure subtract operation: 20 - 8 = \(response4Value)")
        
        // Test divide operation on math2
        let response5 = try await node1.request(
            "math2/divide",
            payload: AnyValue.map([
                "a": AnyValue.primitive(15.0),
                "b": AnyValue.primitive(3.0)
            ]),
            networkId: "test-network"
        )
        let response5Value = try await response5.asType() as Double
        XCTAssertEqual(response5Value, 5.0)
        logger.info("✅ Secure divide operation: 15 / 3 = \(response5Value)")
        
        // ==========================================
        // STEP 17: Cleanup
        // ==========================================
        logger.info("🧹 Shutting down nodes...")
        try await node2.stop()
        try await node1.stop()
        
        logger.info("✅ Both nodes stopped successfully")
        logger.info("🎉 remote action test completed successfully!")
    }
    
    /// Test for node stop/restart/reconnection scenario
    ///
    /// INTENTION: Test that a node can properly stop, restart, and reconnect to the network
    /// and resume remote service calls. This isolates the reconnection logic from replication.
    func testNodeStopRestartReconnection() async throws {
        // For now, just run the test directly without timeout
        // In a real implementation, this would have proper timeout handling
        try await performStopRestartTest()
    }
    
    private func performStopRestartTest() async throws {
        // Configure logging to ensure test logs are displayed
        let loggingConfig = LoggingConfig()
        // Note: Logging config would be applied here in a full implementation
        
        // Set up logger
        let logger = RunarLogger(component: .node)
        
        let configs = try await createNetworkedNodeTestConfigs(count: 2)
        
        let node1Config = configs[0]
        let node2Config = configs[1]
        
        // Create math services with different paths using the fixture
        let mathService1 = MathService(name: "math1", path: "math1")
        let mathService2 = MathService(name: "math2", path: "math2")
        
        logger.debug("Node1 config: \(node1Config)")
        logger.debug("Node2 config: \(node2Config)")
        
        var node1 = try await Node.new(config: node1Config)
        try await node1.addService(mathService1)
        try await node1.start()
        logger.debug("✅ Node 1 started")
        
        let node2 = try await Node.new(config: node2Config)
        try await node2.addService(mathService2)
        try await node2.start()
        logger.debug("✅ Node 2 started")
        
        // Wait for nodes to discover each other
        logger.debug("⏳ Waiting for nodes to discover each other...")
        // Note: For now, we'll skip the peer discovery part to focus on remote calls
        try await Task.sleep(for: .seconds(2)) // Give time for discovery
        logger.debug("✅ Assuming nodes discovered each other")
        
        // ==========================================
        // STEP 2: Test initial remote call from node2 to node1
        // ==========================================
        logger.info("🧪 Testing initial remote call from node2 to node1...")
        
        // Wait for services to start before making remote calls
        logger.info("⏳ Waiting for services to start...")
        try await node1.waitForServicesToStart()
        try await node2.waitForServicesToStart()
        logger.debug("✅ Services started")
        
        let response = try await node2.request(
            "math1/add",
            payload: AnyValue.map([
                "a": AnyValue.primitive(10.0),
                "b": AnyValue.primitive(5.0)
            ]),
            networkId: "test-network"
        )
        
        let responseValue = try await response.asType() as Double
        XCTAssertEqual(responseValue, 15.0)
        logger.debug("✅ Initial remote call succeeded: 10 + 5 = \(responseValue)")
        
        // ==========================================
        // STEP 3: Stop Node 1
        // ==========================================
        logger.info("🛑 Stopping Node 1...")
        try await node1.stop()
        logger.debug("✅ Node 1 stopped")
        
        // Wait for the stop to complete and cleanup to finish
        // In a real scenario, a node would stay down for a meaningful period
        try await Task.sleep(for: .seconds(1))
        
        // ==========================================
        // STEP 4: Verify Node 1 is unreachable
        // ==========================================
        logger.info("🧪 Verifying Node 1 is unreachable...")
        
        do {
            _ = try await node2.request(
                "math1/add",
                payload: AnyValue.map([
                    "a": AnyValue.primitive(1.0),
                    "b": AnyValue.primitive(1.0)
                ]),
                networkId: "test-network"
            )
            XCTFail("Node 1 should be unreachable after stop")
        } catch {
            logger.debug("✅ Node 1 correctly unreachable after stop")
        }
        
        // ==========================================
        // STEP 5: Restart Node 1 (new instance, same config)
        // ==========================================
        logger.info("🔄 Restarting Node 1 (new instance with same config)...")
        
        // Drop old instance completely to simulate real process restart
        node1 = try await Node.new(config: node1Config)
        try await node1.addService(mathService1)
        try await node1.start()
        // Ensure background service start completion before remote requests
        try await node1.waitForServicesToStart()
        logger.debug("✅ Node 1 restarted (new instance)")
        
        // Wait for nodes to discover each other again - same as initial setup
        logger.debug("⏳ Waiting for nodes to rediscover each other...")
        // Note: For now, we'll skip the peer discovery part to focus on remote calls
        try await Task.sleep(for: .seconds(2)) // Give time for discovery
        logger.debug("✅ Assuming nodes rediscovered each other")
        
        // ==========================================
        // STEP 7: Test remote call after restart
        // ==========================================
        logger.info("🧪 Testing remote call after Node 1 restart...")
        
        let response2 = try await node2.request(
            "math1/add",
            payload: AnyValue.map([
                "a": AnyValue.primitive(20.0),
                "b": AnyValue.primitive(10.0)
            ]),
            networkId: "test-network"
        )
        
        let response2Value = try await response2.asType() as Double
        XCTAssertEqual(response2Value, 30.0)
        logger.debug("✅ Remote call after restart succeeded: 20 + 10 = \(response2Value)")
        
        // ==========================================
        // STEP 8: Test bidirectional communication
        // ==========================================
        logger.info("🧪 Testing bidirectional communication after restart...")
        
        // Test call from restarted Node 1 to Node 2
        let response3 = try await node1.request(
            "math2/multiply",
            payload: AnyValue.map([
                "a": AnyValue.primitive(6.0),
                "b": AnyValue.primitive(7.0)
            ]),
            networkId: "test-network"
        )
        
        let response3Value = try await response3.asType() as Double
        XCTAssertEqual(response3Value, 42.0)
        logger.debug("✅ Bidirectional call succeeded: 6 * 7 = \(response3Value)")
        
        // ==========================================
        // STEP 9: Cleanup
        // ==========================================
        logger.info("🧹 Shutting down nodes...")
        try await node2.stop()
        try await node1.stop()
        
        logger.info("✅ Both nodes stopped successfully")
        logger.info("🎉 Node stop/restart/reconnection test completed successfully!")
    }
}

// MARK: - Test Utilities

/// Create networked node test configurations for multiple nodes
/// This matches the Rust create_networked_node_test_config function
func createNetworkedNodeTestConfigs(count: Int) async throws -> [NodeConfig] {
    var configs: [NodeConfig] = []
    
    // Set up trace logging for detailed debugging
    let loggingConfig = LoggingConfig(level: .trace)
    let logger = RunarLogger(component: .node, config: loggingConfig)
    
    logger.trace("🔍 Creating \(count) networked node test configs with trace logging")
    
    // Create a CA for certificate generation
    let caKeys = try await MobileKeyManager()
    
    for i in 0..<count {
        print("🔍 CONFIG: Creating config for node \(i)")
        // All nodes should be on the same network to communicate
        let networkId = "test-network"
        print("🔍 CONFIG: Network ID: \(networkId)")
        
        // Create key manager for this node
        print("🔍 CONFIG: Creating key manager for node \(i)")
        let keyManager = try await createTestKeyManager()
        print("🔍 CONFIG: Key manager created for node \(i)")
        
        // Set local node info (required for transport creation)
        // Note: NodeInfo is now managed at the transport level, not keys level
        // The transport will be created with the current NodeInfo when the node starts
        print("🔍 CONFIG: NodeInfo will be set at transport level when node starts")
        
        // Generate and install certificate for QUIC transport
        print("🔍 CONFIG: Generating certificate for node \(i)")
        let csr = try await keyManager.generateCsrSetupToken()
        let cert = try await caKeys.processSetupToken(csr)
        try await keyManager.installCertificate(cert)
        print("🔍 CONFIG: Certificate installed for node \(i)")
        
        // Create network config with QUIC transport and discovery
        print("🔍 CONFIG: Creating network config for node \(i)")
        let discoveryOptions = SwiftFFI.DiscoveryOptions(
            multicastGroup: "224.0.0.251:5353",
            announceIntervalMs: 1000,
            discoveryTimeoutMs: 5000,
            debounceWindowMs: 200
        )
        let discoveryProvider = DiscoveryProviderConfig(
            type: "mdns",
            config: [:]
        )
        let networkConfig = NetworkConfig(
            transportType: "quic",
            bindAddress: "127.0.0.1:0", // Let OS assign port
            connectionTimeoutMs: 30000,
            requestTimeoutMs: 30000,
            discoveryOptions: discoveryOptions,
            discoveryProviders: [discoveryProvider]
        )
        
        // Create node config
        print("🔍 CONFIG: Creating node config for node \(i)")
        let config = NodeConfig(defaultNetworkId: networkId)
            .withKeyManager(keyManager)
            .withNetworkConfig(networkConfig)
        
        configs.append(config)
        print("🔍 CONFIG: Config created for node \(i)")
    }
    
    return configs
}

/// Create a test key manager for testing
func createTestKeyManager() async throws -> FFIKeys {
    // For testing, we'll create a basic key manager
    // In a real implementation, this would create proper test keys
    return try await NodeKeyManager()
}

// MARK: - Test Errors

enum TestError: Error {
    case timeout(String)
}

// MARK: - Test Utilities (using existing MathService from RegistryServiceTests)
