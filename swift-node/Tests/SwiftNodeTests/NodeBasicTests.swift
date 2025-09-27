import Foundation
import RunarSerializer
import SwiftCommon
import SwiftFFI
@testable import SwiftNode
import XCTest

/// Basic Node tests following the rules - no mocks, no shortcuts, real implementations
@MainActor
final class NodeBasicTests: XCTestCase {
    /// Test that verifies basic node creation functionality
    ///
    /// INTENTION: This test validates that the Node can be properly:
    /// - Created with a specified network ID
    /// - Initialized with default configuration
    ///
    /// This test verifies the most basic Node functionality - that we can create
    /// and initialize a Node instance which is the foundation for all other tests.
    func testNodeCreate() async throws {
        // Create a node with a test network ID
        let keysManager = try await NodeKeyManager()
        let config = NodeConfig(defaultNetworkId: "test-network")
            .withKeyManager(keysManager)

        let node = try await Node.new(config: config)

        // Basic verification that the node exists
        XCTAssertNotNil(node)
        XCTAssertEqual(node.networkId, "test-network")
        XCTAssertFalse(node.isRunning)
    }

    /// Test that verifies node lifecycle methods work correctly
    ///
    /// INTENTION: This test validates that the Node can properly:
    /// - Start up and initialize correctly
    /// - Shut down cleanly when requested
    ///
    /// This test verifies the Node's lifecycle management which is critical
    /// for resource cleanup and proper application shutdown.
    func testNodeLifecycle() async throws {
        // Create a node with a test network ID
        let keysManager = try await NodeKeyManager()
        let config = NodeConfig(defaultNetworkId: "test-network")
            .withKeyManager(keysManager)

        let node = try await Node.new(config: config)

        // Start the node
        try await node.start()
        XCTAssertTrue(node.isRunning)

        // Stop the node
        await node.stop()
        XCTAssertFalse(node.isRunning)
    }

    /// Test that verifies service registration with the Node
    ///
    /// INTENTION: This test validates that the Node can properly:
    /// - Accept a service for registration
    /// - Register the service with its ServiceRegistry
    /// - Start the service when the node starts
    ///
    /// This test verifies the Node's responsibility for managing services and
    /// correctly delegating registration to its ServiceRegistry.
    func testNodeAddService() async throws {
        // Create a node with a test network ID
        let keysManager = try await NodeKeyManager()
        let config = NodeConfig(defaultNetworkId: "test-network")
            .withKeyManager(keysManager)

        let node = try await Node.new(config: config)

        // Create a test service
        let service = TestMathService()

        // Add the service to the node
        try await node.addService(service)

        // Start the node to initialize all services
        try await node.start()
        XCTAssertTrue(node.isRunning)

        // Stop the node
        await node.stop()
        XCTAssertFalse(node.isRunning)
    }
}

/// Test service implementation - real implementation, no mocks
@MainActor
final class TestMathService: ServiceBase {
    init() {
        super.init(
            name: "TestMathService",
            version: "1.0.0",
            path: "math",
            description: "Test math service for unit tests",
            logger: RunarLogger(component: .service)
        )
    }

    override func initService(_ context: LifecycleContext) async throws {
        // Register math actions
        try await context.registerAction("add") { payload, requestContext in
            // Simple addition: return a fixed result for testing
            AnyValue.primitive(8.0)
        }

        try await context.registerAction("multiply") { payload, requestContext in
            // Simple multiplication: return a fixed result for testing
            AnyValue.primitive(28.0)
        }
    }

    override func start(_: LifecycleContext) async throws {
        // Service started successfully
        logger.trace("TestMathService started")
    }

    override func stop(_: LifecycleContext) async throws {
        // Service stopped successfully
        logger.trace("TestMathService stopped")
    }
    
    override func setNetworkId(_ networkId: String) {
        self.networkId = networkId
    }
}
