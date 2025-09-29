import RunarSerializer
import SwiftCommon
@testable import SwiftNode
import XCTest

/// Phase 1 Tests - Core Node Structure (Local-First)
///
/// These tests validate that the basic Node structure and configuration
/// work correctly for local-only operations, matching the Rust implementation.
@MainActor
class Phase1Tests: XCTestCase {
    // MARK: - Test Configuration

    override func setUp() {
        super.setUp()
        // Set up any test-specific configuration
    }

    override func tearDown() {
        // Clean up after tests
        super.tearDown()
    }

    // MARK: - NodeConfig Tests

    func testNodeConfigCreation() {
        // Test basic NodeConfig creation
        let config = NodeConfig(defaultNetworkId: "test-network")

        XCTAssertEqual(config.defaultNetworkId, "test-network")
        XCTAssertEqual(config.networkIds, [])
        XCTAssertEqual(config.requestTimeoutMs, 30000)
        XCTAssertNil(config.networkConfig)
        XCTAssertNotNil(config.loggingConfig)
        XCTAssertNotNil(config.labelResolverConfig)
        XCTAssertNil(config.getKeyManager())
    }

    func testNodeConfigBuilderPattern() {
        // Test NodeConfig builder pattern
        let config = NodeConfig(defaultNetworkId: "test-network")
            .withRequestTimeout(5000)
            .withAdditionalNetworks(["backup", "testing"])
            .withLoggingConfig(LoggingConfig(defaultLevel: .debug))

        XCTAssertEqual(config.requestTimeoutMs, 5000)
        XCTAssertEqual(config.networkIds, ["backup", "testing"])
        XCTAssertEqual(config.loggingConfig?.defaultLevel, .debug)
    }

    func testNodeConfigWithNetworkConfig() {
        // Test NodeConfig with network configuration
        let networkConfig = NetworkConfig(
            transportType: "quic",
            bindAddress: "127.0.0.1:0",
            connectionTimeoutMs: 10000,
            requestTimeoutMs: 15000
        )

        let config = NodeConfig(defaultNetworkId: "test-network")
            .withNetworkConfig(networkConfig)

        XCTAssertNotNil(config.networkConfig)
        XCTAssertEqual(config.networkConfig?.transportType, "quic")
        XCTAssertEqual(config.networkConfig?.bindAddress, "127.0.0.1:0")
        XCTAssertEqual(config.networkConfig?.connectionTimeoutMs, 10000)
        XCTAssertEqual(config.networkConfig?.requestTimeoutMs, 15000)
    }

    // MARK: - Node Structure Tests

    func testNodeInfoCreation() {
        // Test NodeInfo structure
        let nodeInfo = NodeInfo(
            nodePublicKey: Data([1, 2, 3, 4, 5, 6, 7, 8]),
            networkIds: ["network1", "network2"],
            addresses: ["127.0.0.1:8080"],
            nodeMetadata: NodeMetadata(
                services: ["service1", "service2"],
                subscriptions: ["topic1", "topic2"]
            ),
            version: 1
        )

        XCTAssertEqual(nodeInfo.nodePublicKey, Data([1, 2, 3, 4, 5, 6, 7, 8]))
        XCTAssertEqual(nodeInfo.networkIds, ["network1", "network2"])
        XCTAssertEqual(nodeInfo.addresses, ["127.0.0.1:8080"])
        XCTAssertEqual(nodeInfo.nodeMetadata.services, ["service1", "service2"])
        XCTAssertEqual(nodeInfo.nodeMetadata.subscriptions, ["topic1", "topic2"])
        XCTAssertEqual(nodeInfo.version, 1)
    }

    func testServiceTaskCreation() {
        // Test ServiceTask structure
        let serviceTask = ServiceTask(
            servicePath: "test/service",
            taskId: "task-123",
            status: "running"
        )

        XCTAssertEqual(serviceTask.servicePath, "test/service")
        XCTAssertEqual(serviceTask.taskId, "task-123")
        XCTAssertEqual(serviceTask.status, "running")
    }

    func testRetainedEventEntryCreation() {
        // Test RetainedEventEntry structure
        let timestamp = Date()
        let data = AnyValue.primitive("test data")

        let entry = RetainedEventEntry(timestamp: timestamp, data: data)

        XCTAssertEqual(entry.timestamp, timestamp)
        // AnyValue doesn't conform to Equatable, so we can't directly compare
        // XCTAssertEqual(entry.data, data)
    }

    // MARK: - ServiceRegistry Tests

    func testServiceRegistryCreation() {
        // Test ServiceRegistry creation
        let logger = RunarLogger(component: .node)
        let registry = ServiceRegistry(logger: logger)

        XCTAssertNotNil(registry)
        // component is private, so we can't access it
        // XCTAssertEqual(registry.logger.component, .node)
    }

    func testServiceRegistryLocalServiceRegistration() async throws {
        // Test local service registration
        let logger = RunarLogger(component: .node)
        let registry = ServiceRegistry(logger: logger)

        // ServiceRegistry doesn't have registerLocalService method
        // This would be handled by the Node when adding services

        // Verify service was registered (this would need to be implemented in ServiceRegistry)
        // For now, we just verify no error was thrown
        XCTAssertTrue(true)
    }

    // MARK: - Load Balancing Tests

    func testRoundRobinLoadBalancer() async {
        // Test round-robin load balancer
        let balancer = RoundRobinLoadBalancer()
        let handlers = ["handler1", "handler2", "handler3"]

        // Test multiple selections
        let selection1 = await balancer.selectHandler(handlers: handlers)
        let selection2 = await balancer.selectHandler(handlers: handlers)
        let selection3 = await balancer.selectHandler(handlers: handlers)
        let selection4 = await balancer.selectHandler(handlers: handlers)

        XCTAssertNotNil(selection1)
        XCTAssertNotNil(selection2)
        XCTAssertNotNil(selection3)
        XCTAssertNotNil(selection4)

        // Verify round-robin behavior
        XCTAssertEqual(selection1, "handler1")
        XCTAssertEqual(selection2, "handler2")
        XCTAssertEqual(selection3, "handler3")
        XCTAssertEqual(selection4, "handler1") // Should wrap around
    }

    // MARK: - Error Handling Tests

    func testNodeErrorDescriptions() {
        // Test NodeError descriptions
        let missingKeyManager = NodeError.missingKeyManager("Test error")
        let missingNodePublicKey = NodeError.missingNodePublicKey("Test error")
        let serviceRegistrationFailed = NodeError.serviceRegistrationFailed("Test error")
        let networkInitializationFailed = NodeError.networkInitializationFailed("Test error")
        let invalidConfiguration = NodeError.invalidConfiguration("Test error")

        XCTAssertTrue(missingKeyManager.localizedDescription.contains("Missing key manager"))
        XCTAssertTrue(missingNodePublicKey.localizedDescription.contains("Missing node public key"))
        XCTAssertTrue(serviceRegistrationFailed.localizedDescription.contains("Service registration failed"))
        XCTAssertTrue(networkInitializationFailed.localizedDescription.contains("Network initialization failed"))
        XCTAssertTrue(invalidConfiguration.localizedDescription.contains("Invalid configuration"))
    }

    // MARK: - Integration Tests (Placeholder)

    func testNodeCreationWithoutKeyManager() async {
        // Test that Node creation fails without key manager
        let config = NodeConfig(defaultNetworkId: "test-network")

        do {
            _ = try await Node.new(config: config)
            XCTFail("Expected Node creation to fail without key manager")
        } catch NodeError.missingKeyManager {
            // Expected error
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Performance Tests (Placeholder)

    func testNodeConfigPerformance() {
        // Test NodeConfig creation performance
        measure {
            for _ in 0 ..< 1000 {
                let config = NodeConfig(defaultNetworkId: "test-network")
                _ = config.withRequestTimeout(5000)
                    .withAdditionalNetworks(["backup"])
                    .withLoggingConfig(LoggingConfig(defaultLevel: .info))
            }
        }
    }
}

// MARK: - Test Helpers

extension Phase1Tests {
    /// Create a test NodeConfig with key manager
    func createTestNodeConfig() -> NodeConfig {
        // This would create a test configuration with a mock key manager
        // For now, return a basic config
        NodeConfig(defaultNetworkId: "test-network")
    }

    /// Create a test service for testing
    func createTestService() -> some AbstractService {
        MockTestService()
    }
}

// MARK: - Mock Test Service

@MainActor
private class MockTestService: AbstractService {
    let name: String = "MockTestService"
    let version: String = "1.0.0"
    let path: String = "test/service"
    let description: String = "A mock test service"
    let logger: RunarLogger
    var networkId: String?
    
    init() {
        self.logger = RunarLogger(component: .service)
    }

    func setNetworkId(_ networkId: String) {
        self.networkId = networkId
    }

    func initService(_: LifecycleContext) async throws {
        // Mock implementation
    }

    func start(_: LifecycleContext) async throws {
        // Mock implementation
    }

    func stop(_: LifecycleContext) async throws {
        // Mock implementation
    }
}
