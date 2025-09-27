import Foundation
import RunarSerializer
import SwiftCommon
import SwiftFFI
@testable import SwiftNode
import XCTest

/// Node request handling tests following the rules - no mocks, no shortcuts, real implementations
final class NodeRequestTests: XCTestCase {
    /// Test that verifies request handling in the Node
    ///
    /// INTENTION: This test validates that the Node can properly:
    /// - Find a service for a specific request
    /// - Forward the request to the appropriate service
    /// - Return the service's response
    ///
    /// This test verifies one of the Node's core responsibilities - request routing
    /// and handling. The Node should find the right service and forward the request.
    func testNodeRequest() async throws {
        // Create a node with a test network ID
        let keysManager = try await NodeKeyManager()
        let config = NodeConfig(defaultNetworkId: "test-network")
            .withKeyManager(keysManager)

        let node = try await Node.new(config: config)

        // Create a test service
        let service = await TestMathService()

        // Add the service to the node
        try await node.addService(service)

        // Start the node to initialize all services
        try await node.start()

        // Create parameters for addition
        let params = AnyValue.map([
            "a": AnyValue.primitive(5.0),
            "b": AnyValue.primitive(3.0),
        ])

        // Make a request to the math service's add action
        let result = try await node.serviceRegistry.request("math/add", payload: params, networkId: "test-network")

        // Verify the result
        let resultValue = try await result.asType() as Double
        XCTAssertEqual(resultValue, 8.0, "Addition should work correctly")
    }

    /// Test that verifies multiplication request handling
    func testNodeRequestMultiply() async throws {
        // Create a node with a test network ID
        let keysManager = try await NodeKeyManager()
        let config = NodeConfig(defaultNetworkId: "test-network")
            .withKeyManager(keysManager)

        let node = try await Node.new(config: config)

        // Create a test service
        let service = await TestMathService()

        // Add the service to the node
        try await node.addService(service)

        // Start the node to initialize all services
        try await node.start()

        // Create parameters for multiplication
        let params = AnyValue.map([
            "a": AnyValue.primitive(4.0),
            "b": AnyValue.primitive(7.0),
        ])

        // Make a request to the math service's multiply action
        let result = try await node.serviceRegistry.request("math/multiply", payload: params, networkId: "test-network")

        // Verify the result
        let resultValue = try await result.asType() as Double
        XCTAssertEqual(resultValue, 28.0, "Multiplication should work correctly")
    }

    /// Test that verifies error handling for invalid requests
    func testNodeRequestError() async throws {
        // Create a node with a test network ID
        let keysManager = try await NodeKeyManager()
        let config = NodeConfig(defaultNetworkId: "test-network")
            .withKeyManager(keysManager)

        let node = try await Node.new(config: config)

        // Start the node (no services added)
        try await node.start()

        // Try to make a request to a non-existent service
        do {
            _ = try await node.serviceRegistry.request("nonexistent/action", payload: nil as AnyValue?, networkId: "test-network")
            XCTFail("Request should have failed for non-existent service")
        } catch {
            // Expected to fail
            XCTAssertTrue(error is ServiceRegistryError)
        }
    }
}
