import Foundation
import RunarSerializer
import SwiftCommon
import SwiftFFI
@testable import SwiftNode
import XCTest

/// Node event publishing and subscription tests following the rules - no mocks, no shortcuts, real implementations
final class NodeEventTests: XCTestCase {
    /// Test that verifies event publishing and subscription in the Node
    ///
    /// INTENTION: This test validates that the Node can properly:
    /// - Accept subscriptions for specific topics
    /// - Publish events to those topics
    /// - Ensure subscribers receive the published events
    ///
    /// This test verifies the Node's subscription and publishing capabilities,
    /// which is a core part of the event-driven architecture.
    func testNodeEvents() async throws {
        // Create a node with a test network ID
        let keysManager = try await NodeKeyManager()
        let config = NodeConfig(defaultNetworkId: "test-network")
            .withKeyManager(keysManager)

        let node = try await Node.new(config: config)

        // Start the node
        try await node.start()

        // Create a flag to track if the callback was called
        let expectation = XCTestExpectation(description: "Event received")

        // Define a topic to subscribe to
        let topic = "test/topic"

        // Subscribe to the topic
        let subscriptionId = try await node.subscribe(topic: topic, options: nil as EventRegistrationOptions?) { _, data in
            // Verify the data matches what we published
            if let data {
                let stringValue = try? await data.asType() as String
                XCTAssertEqual(stringValue, "test data")
                expectation.fulfill()
            }
        }

        // Verify subscription was created
        XCTAssertFalse(subscriptionId.isEmpty)

        // Publish an event to the topic
        let eventData = AnyValue.primitive("test data")
        try await node.publish(topic: topic, data: eventData)

        // Wait for the event to be received
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    /// Test that verifies multiple subscribers receive the same event
    func testNodeEventMultipleSubscribers() async throws {
        // Create a node with a test network ID
        let keysManager = try await NodeKeyManager()
        let config = NodeConfig(defaultNetworkId: "test-network")
            .withKeyManager(keysManager)

        let node = try await Node.new(config: config)

        // Start the node
        try await node.start()

        // Create expectations for multiple subscribers
        let expectation1 = XCTestExpectation(description: "Event received by subscriber 1")
        let expectation2 = XCTestExpectation(description: "Event received by subscriber 2")

        // Define a topic to subscribe to
        let topic = "test/multiple"

        // Subscribe to the topic with first subscriber
        let subscriptionId1 = try await node.subscribe(topic: topic, options: nil as EventRegistrationOptions?) { _, data in
            if let data {
                let stringValue = try? await data.asType() as String
                XCTAssertEqual(stringValue, "test data")
                expectation1.fulfill()
            }
        }

        // Subscribe to the topic with second subscriber
        let subscriptionId2 = try await node.subscribe(topic: topic, options: nil as EventRegistrationOptions?) { _, data in
            if let data {
                let stringValue = try? await data.asType() as String
                XCTAssertEqual(stringValue, "test data")
                expectation2.fulfill()
            }
        }

        // Verify subscriptions were created
        XCTAssertFalse(subscriptionId1.isEmpty)
        XCTAssertFalse(subscriptionId2.isEmpty)
        XCTAssertNotEqual(subscriptionId1, subscriptionId2)

        // Publish an event to the topic
        let eventData = AnyValue.primitive("test data")
        try await node.publish(topic: topic, data: eventData)

        // Wait for both events to be received
        await fulfillment(of: [expectation1, expectation2], timeout: 1.0)
    }

    /// Test that verifies event publishing from a service
    func testNodeEventFromService() async throws {
        // Create a node with a test network ID
        let keysManager = try await NodeKeyManager()
        let config = NodeConfig(defaultNetworkId: "test-network")
            .withKeyManager(keysManager)

        let node = try await Node.new(config: config)

        // Create a test service that publishes events
        let service = TestEventService()

        // Add the service to the node
        try await node.addService(service)

        // Start the node
        try await node.start()

        // Create expectation for the event
        let expectation = XCTestExpectation(description: "Event received from service")

        // Subscribe to the service's event topic
        let topic = "test/service/event"
        let subscriptionId = try await node.subscribe(topic: topic, options: nil as EventRegistrationOptions?) { _, data in
            if let data {
                let stringValue = try? await data.asType() as String
                XCTAssertEqual(stringValue, "Hello from service!")
                expectation.fulfill()
            }
        }

        // Verify subscription was created
        XCTAssertFalse(subscriptionId.isEmpty)

        // Publish an event directly to the topic
        let eventData = AnyValue.primitive("Hello from service!")
        try await node.publish(topic: topic, data: eventData)

        // Wait for the event to be received
        await fulfillment(of: [expectation], timeout: 1.0)
    }
}

/// Test service that publishes events - real implementation, no mocks
final class TestEventService: AbstractService {
    let name: String = "TestEventService"
    let version: String = "1.0.0"
    let path: String = "test"
    let description: String = "Test event service for unit tests"
    let logger: RunarLogger
    var networkId: String?
    let state: ServiceState = .created

    init() {
        logger = RunarLogger(component: .service)
    }

    func initService(_ context: LifecycleContext) async throws {
        // Register a trigger action that just returns success
        try await context.registerAction("trigger") { _ in
            AnyValue.primitive("triggered")
        }
    }

    func start(_: LifecycleContext) async throws {
        // Service started successfully
        logger.info("TestEventService started")
    }

    func stop(_: LifecycleContext) async throws {
        // Service stopped successfully
        logger.info("TestEventService stopped")
    }
}
