import RunarSerializer
import SwiftCommon
import SwiftFFI
@testable import SwiftNode
import XCTest

@MainActor
final class ServiceTests: XCTestCase {

    // Swift logger for trace-level logging
    private var testLogger: RunarLogger!

    override func setUp() async throws {
        try await super.setUp()

        // Set global logger config to trace level for all tests
        LoggerConfigManager.shared.globalConfig = LoggerConfig(
            level: .trace,
            includeTimestamp: true,
            includeComponent: true,
            includeContext: true
        )

        // Create root logger for this test with test name as context
        testLogger = RunarLogger.root(component: .custom("ServiceTests"))
    }
    
    func testKeysServiceLifecycle() async throws {
        // Test KeysService with real Node implementation
        let logger = testLogger.child(component: .node)
        
        // Create real Node with real key manager using proper API
        let nodeKeysManager = try await NodeKeyManager()
        let defaultNetworkId = "test-network"
        
        // Create NodeConfig and set key manager
        var config = NodeConfig(defaultNetworkId: defaultNetworkId)
        config = config.withKeyManager(nodeKeysManager)
        
        // Create Node using the proper static factory method
        let node = try await Node.new(config: config)
        
        // Test Node initialization (which includes KeysService)
        try await node.start()
        
        // Test that the node is running and has key management capabilities
        XCTAssertNotNil(node.keysManager)
        
        // Test stopping the node (which stops all services including KeysService)
        try await node.stop()
    }

    func testRegistryServiceLifecycle() async throws {
        // Test RegistryService with real Node implementation
        let logger = testLogger.child(component: .registry)
        
        // Create real Node with real key manager using proper API
        let nodeKeysManager = try await NodeKeyManager()
        let defaultNetworkId = "test-network"
        
        // Create NodeConfig and set key manager
        var config = NodeConfig(defaultNetworkId: defaultNetworkId)
        config = config.withKeyManager(nodeKeysManager)
        
        // Create Node using the proper static factory method
        let node = try await Node.new(config: config)
        
        // Test Node initialization (which includes RegistryService)
        try await node.start()
        
        // Test that the node has service registry capabilities
        XCTAssertNotNil(node.serviceRegistry)
        
        // Test service registration through the real node
        let testHandler: ActionHandler = { params, context in
            return AnyValue.primitive("test-response")
        }
        
        try await node.registerAction(
            networkId: defaultNetworkId,
            servicePath: "test-service",
            action: "test-action",
            handler: testHandler
        )
        
        // Test stopping the node (which stops all services including RegistryService)
        try await node.stop()
    }


    func testServiceStateTransitions() async throws {
        // Test service state transitions with real Node implementation
        let logger = testLogger.child(component: .node)
        
        // Create real Node with real key manager using proper API
        let nodeKeysManager = try await NodeKeyManager()
        let defaultNetworkId = "test-network"
        
        // Create NodeConfig and set key manager
        var config = NodeConfig(defaultNetworkId: defaultNetworkId)
        config = config.withKeyManager(nodeKeysManager)
        
        // Create Node using the proper static factory method
        let node = try await Node.new(config: config)

        // Test state transitions through real node lifecycle
        try await node.start()
        
        // Verify node is running
        XCTAssertNotNil(node.keysManager)
        XCTAssertNotNil(node.serviceRegistry)
        
        // Test stopping the node
        try await node.stop()
    }

    func testServiceErrorHandling() async throws {
        // Test service error handling with real Node implementation
        let logger = testLogger.child(component: .node)
        
        // Test error handling during Node creation with invalid parameters
        do {
            // Test with missing key manager (should fail)
            let defaultNetworkId = "test-network"
            var config = NodeConfig(defaultNetworkId: defaultNetworkId)
            // Don't set key manager - this should cause an error
            
            let _ = try await Node.new(config: config)
            
            // If we get here, the test should fail
            XCTFail("Expected error for missing key manager")
        } catch {
            // Expected error for invalid parameters
            XCTAssertTrue(error is NodeError)
        }
        
        // Test normal flow with valid parameters
        let nodeKeysManager = try await NodeKeyManager()
        let defaultNetworkId = "test-network"
        
        // Create NodeConfig and set key manager
        var config = NodeConfig(defaultNetworkId: defaultNetworkId)
        config = config.withKeyManager(nodeKeysManager)
        
        // Create Node using the proper static factory method
        let node = try await Node.new(config: config)
        
        // Test normal initialization
        try await node.start()
        try await node.stop()
    }
}


