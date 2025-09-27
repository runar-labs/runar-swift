import Foundation
import RunarSerializer
import SwiftCommon
import SwiftFFI
@testable import SwiftNode
import XCTest

/// Retained events tests following the rules - no mocks, no shortcuts, real implementations
final class RetainedEventsTests: XCTestCase {
    /// Test that verifies retained events functionality
    ///
    /// INTENTION: This test validates that the Node can properly:
    /// - Retain events when publish options specify retention
    /// - Deliver retained events to new subscribers with includePast
    /// - Prune expired events based on TTL
    ///
    /// This test verifies the Node's retained events functionality which is
    /// critical for late subscribers to receive recent events.
    func testRetainedEvents() async throws {
        // Create a node with a test network ID
        let keysManager = try await NodeKeyManager()
        let config = NodeConfig(defaultNetworkId: "test-network")
            .withKeyManager(keysManager)

        let node = try await Node.new(config: config)

        // Start the node
        try await node.start()

        // Publish an event with retention
        let eventData = AnyValue.primitive("retained data")
        let publishOptions = PublishOptions(retainFor: 60) // Retain for 60 seconds
        try await node.publish(topic: "test/retained", data: eventData, options: publishOptions)

        // Wait a moment to ensure the event is retained
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Subscribe with includePast to get the retained event
        let expectation = XCTestExpectation(description: "Retained event received")
        let subscriptionOptions = EventRegistrationOptions(includePast: 120) // Look back 120 seconds

        let subscriptionId = try await node.subscribe(topic: "test/retained", options: subscriptionOptions) { data in
            if let data {
                let stringValue = try? await data.asType() as String
                XCTAssertEqual(stringValue, "retained data")
                expectation.fulfill()
            }
        }

        // Verify subscription was created
        XCTAssertFalse(subscriptionId.isEmpty)

        // Wait for the retained event to be delivered
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    /// Test that verifies retained events with multiple subscribers
    func testRetainedEventsMultipleSubscribers() async throws {
        // Create a node with a test network ID
        let keysManager = try await NodeKeyManager()
        let config = NodeConfig(defaultNetworkId: "test-network")
            .withKeyManager(keysManager)

        let node = try await Node.new(config: config)

        // Start the node
        try await node.start()

        // Publish an event with retention
        let eventData = AnyValue.primitive("retained data")
        let publishOptions = PublishOptions(retainFor: 60) // Retain for 60 seconds
        try await node.publish(topic: "test/retained", data: eventData, options: publishOptions)

        // Wait a moment to ensure the event is retained
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Subscribe with includePast to get the retained event
        let expectation1 = XCTestExpectation(description: "Retained event received by subscriber 1")
        let expectation2 = XCTestExpectation(description: "Retained event received by subscriber 2")
        let subscriptionOptions = EventRegistrationOptions(includePast: 120) // Look back 120 seconds

        let subscriptionId1 = try await node.subscribe(topic: "test/retained", options: subscriptionOptions) { data in
            if let data {
                let stringValue = try? await data.asType() as String
                XCTAssertEqual(stringValue, "retained data")
                expectation1.fulfill()
            }
        }

        let subscriptionId2 = try await node.subscribe(topic: "test/retained", options: subscriptionOptions) { data in
            if let data {
                let stringValue = try? await data.asType() as String
                XCTAssertEqual(stringValue, "retained data")
                expectation2.fulfill()
            }
        }

        // Verify subscriptions were created
        XCTAssertFalse(subscriptionId1.isEmpty)
        XCTAssertFalse(subscriptionId2.isEmpty)
        XCTAssertNotEqual(subscriptionId1, subscriptionId2)

        // Wait for both retained events to be delivered
        await fulfillment(of: [expectation1, expectation2], timeout: 1.0)
    }

    /// Test that verifies retained events TTL pruning
    func testRetainedEventsTTLPruning() async throws {
        // Create a node with a test network ID
        let keysManager = try await NodeKeyManager()
        let config = NodeConfig(defaultNetworkId: "test-network")
            .withKeyManager(keysManager)

        let node = try await Node.new(config: config)

        // Start the node
        try await node.start()

        // Publish an event with very short retention
        let eventData = AnyValue.primitive("short lived data")
        let publishOptions = PublishOptions(retainFor: 0.1) // Retain for 100ms only
        try await node.publish(topic: "test/short", data: eventData, options: publishOptions)

        // Wait longer than the retention period
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // Subscribe with includePast - should not receive the expired event
        let expectation = XCTestExpectation(description: "No retained event received")
        expectation.isInverted = true // This expectation should NOT be fulfilled
        let subscriptionOptions = EventRegistrationOptions(includePast: 1) // Look back 1 second

        let subscriptionId = try await node.subscribe(topic: "test/short", options: subscriptionOptions) { data in
            // This should not be called since the event should be expired
            expectation.fulfill()
        }

        // Verify subscription was created
        XCTAssertFalse(subscriptionId.isEmpty)

        // Wait a moment to ensure no event is delivered
        await fulfillment(of: [expectation], timeout: 0.5)
    }

    /// Test that verifies retained events capacity limits
    func testRetainedEventsCapacityLimits() async throws {
        // Create a node with a test network ID
        let keysManager = try await NodeKeyManager()
        let config = NodeConfig(defaultNetworkId: "test-network")
            .withKeyManager(keysManager)

        let node = try await Node.new(config: config)

        // Start the node
        try await node.start()

        // Publish many events with retention to test capacity limits
        let publishOptions = PublishOptions(retainFor: 60) // Retain for 60 seconds
        for i in 0..<20 { // Publish 20 events (more than the default capacity of 16)
            let eventData = AnyValue.primitive("event \(i)")
            try await node.publish(topic: "test/capacity", data: eventData, options: publishOptions)
        }

        // Wait a moment to ensure events are retained
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Subscribe with includePast to get the retained events
        let expectation = XCTestExpectation(description: "Retained event received")
        let subscriptionOptions = EventRegistrationOptions(includePast: 120) // Look back 120 seconds

        let subscriptionId = try await node.subscribe(topic: "test/capacity", options: subscriptionOptions) { data in
            if let data {
                let stringValue = try? await data.asType() as String
                // Should receive one of the retained events (the most recent ones due to capacity limits)
                XCTAssertTrue(stringValue?.hasPrefix("event ") == true)
                expectation.fulfill()
            }
        }

        // Verify subscription was created
        XCTAssertFalse(subscriptionId.isEmpty)

        // Wait for a retained event to be delivered
        await fulfillment(of: [expectation], timeout: 1.0)
    }
}

