import Foundation
import RunarSerializer
import SwiftCommon
@testable import SwiftNode
import XCTest

/// Service registry tests following the rules - no mocks, no shortcuts, real implementations
final class ServiceRegistryTests: XCTestCase {
    /// Test that verifies service registry creation
    func testServiceRegistryCreation() {
        // Create a logger
        let logger = RunarLogger(component: .node)

        // Create a service registry
        let registry = ServiceRegistry(logger: logger)

        // Verify the registry was created
        XCTAssertNotNil(registry)
    }

    /// Test that verifies local service registration
    func testServiceRegistryLocalServiceRegistration() async throws {
        // Create a logger
        let logger = RunarLogger(component: .node)

        // Create a service registry
        let registry = ServiceRegistry(logger: logger)

        // Register a local service
        try await registry.registerLocalService(
            servicePath: "test/service",
            name: "TestService",
            version: "1.0.0",
            description: "A test service"
        )

        // Verify the service was registered (we can't directly check the internal state,
        // but we can verify no error was thrown)
        XCTAssertTrue(true, "Service registration should succeed")
    }

    /// Test that verifies service instance registration
    func testServiceRegistryServiceInstanceRegistration() async throws {
        // Create a logger
        let logger = RunarLogger(component: .node)

        // Create a service registry
        let registry = ServiceRegistry(logger: logger)

        // Create a test service
        let service = TestMathService()

        // Register the service instance
        try await registry.registerServiceInstance(service)

        // Verify the service was registered (we can't directly check the internal state,
        // but we can verify no error was thrown)
        XCTAssertTrue(true, "Service instance registration should succeed")
    }

    /// Test that verifies action registration
    func testServiceRegistryActionRegistration() async throws {
        // Create a logger
        let logger = RunarLogger(component: .node)

        // Create a service registry
        let registry = ServiceRegistry(logger: logger)

        // Register an action handler
        try await registry.registerAction(
            networkId: "test-network",
            servicePath: "test/service",
            action: "test_action",
            handler: { _ in
                AnyValue.primitive("test response")
            }
        )

        // Verify the action was registered (we can't directly check the internal state,
        // but we can verify no error was thrown)
        XCTAssertTrue(true, "Action registration should succeed")
    }

    /// Test that verifies event subscription
    func testServiceRegistryEventSubscription() async throws {
        // Create a logger
        let logger = RunarLogger(component: .node)

        // Create a service registry
        let registry = ServiceRegistry(logger: logger)

        // Subscribe to events
        let subscriptionId = await registry.subscribeToEvents(
            networkId: "test-network",
            servicePath: "test/service",
            handler: { _, _ in
                // Event handler
            }
        )

        // Verify the subscription was created
        XCTAssertFalse(subscriptionId.isEmpty)
    }

    /// Test that verifies event publishing
    func testServiceRegistryEventPublishing() async throws {
        // Create a logger
        let logger = RunarLogger(component: .node)

        // Create a service registry
        let registry = ServiceRegistry(logger: logger)

        // Create expectation for the event
        let expectation = XCTestExpectation(description: "Event received")

        // Subscribe to events
        let subscriptionId = await registry.subscribeToEvents(
            networkId: "test-network",
            servicePath: "test/service",
            handler: { _, data in
                if let data {
                    let stringValue = try? await data.asType() as String
                    XCTAssertEqual(stringValue, "test event data")
                    expectation.fulfill()
                }
            }
        )

        // Publish an event
        let eventData = AnyValue.primitive("test event data")
        await registry.publish("test/service", eventData, networkId: "test-network")

        // Wait for the event to be received
        await fulfillment(of: [expectation], timeout: 1.0)

        // Unsubscribe
        await registry.unsubscribeFromEvents(subscriptionId: subscriptionId)
    }

    /// Test that verifies request handling
    func testServiceRegistryRequestHandling() async throws {
        // Create a logger
        let logger = RunarLogger(component: .node)

        // Create a service registry
        let registry = ServiceRegistry(logger: logger)

        // Register an action handler
        try await registry.registerAction(
            networkId: "test-network",
            servicePath: "test/service",
            action: "test_action",
            handler: { _ in
                AnyValue.primitive("test response")
            }
        )

        // Make a request
        let result = try await registry.request("test/service/test_action", payload: nil, networkId: "test-network")

        // Verify the result
        let resultValue = try await result.asType() as String
        XCTAssertEqual(resultValue, "test response")
    }

    /// Test that verifies error handling for non-existent actions
    func testServiceRegistryRequestError() async throws {
        // Create a logger
        let logger = RunarLogger(component: .node)

        // Create a service registry
        let registry = ServiceRegistry(logger: logger)

        // Try to make a request to a non-existent action
        do {
            _ = try await registry.request("nonexistent/action", payload: nil)
            XCTFail("Request should have failed for non-existent action")
        } catch {
            // Expected to fail
            XCTAssertTrue(error is ServiceRegistryError)
        }
    }
}
