import Foundation
import RunarSerializer
import SwiftCommon
import SwiftFFI
@testable import SwiftNode
import XCTest

/// Test local event dispatch without networking
/// These tests mirror the Rust local_event_dispatch_test.rs exactly
@MainActor
final class LocalEventDispatchTests: XCTestCase {
    // Swift logger for trace-level logging
    private var testLogger: RunarLogger!

    override func setUp() async throws {
        try await super.setUp()

        // Set global logger config to trace level for all tests
        LoggerConfigManager.shared.globalConfig = LoggerConfig(
            level: .info,
            includeTimestamp: true,
            includeComponent: true,
            includeContext: true
        )

        // Create root logger for this test with test name as context
        testLogger = RunarLogger.root(component: .custom("LocalEventDispatchTests"))
    }

    // MARK: - Test Setup

    private func createTestLogger() -> RunarLogger {
        testLogger.child(component: .node)
    }

    // MARK: - Local Event Dispatch Tests

    /// Test local event dispatch with multiple subscribers
    /// Mirrors Rust test_local_event_dispatch_multiple_subscribers exactly
    func testLocalEventDispatchMultipleSubscribers() async throws {
        // Create a node with NO networking (matching Rust exactly)
        let config = try await createNodeTestConfig()
        let node = try await Node.new(config: config)

        // Create counters to track which handlers get called (matching Rust exactly)
        let counter1 = AtomicInteger(initialValue: 0)
        let counter2 = AtomicInteger(initialValue: 0)

        // Create two subscriptions to the same topic BEFORE starting the node (matching Rust exactly)
        let counter1Ref = counter1
        let subId1 = try await node.subscribe(
            topic: "test/event",
            options: EventRegistrationOptions(),
            callback: { _, data in
                Task {
                    await counter1Ref.increment()
                    print("Handler 1 called with data: \(String(describing: data))")
                }
            }
        )

        let counter2Ref = counter2
        let subId2 = try await node.subscribe(
            topic: "test/event",
            options: EventRegistrationOptions(),
            callback: { _, data in
                Task {
                    await counter2Ref.increment()
                    print("Handler 2 called with data: \(String(describing: data))")
                }
            }
        )

        print("Created subscription 1: \(subId1)")
        print("Created subscription 2: \(subId2)")

        // Start the node (matching Rust exactly)
        try await node.start()
        print("Node started")

        // Publish an event (matching Rust exactly)
        let testData = AnyValue.primitive(42.0)
        try await node.publish(topic: "test/event", data: testData)
        print("Event published")

        // Give handlers time to execute (matching Rust exactly)
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Check that both handlers were called (matching Rust exactly)
        let count1 = await counter1.value
        let count2 = await counter2.value

        print("Counter 1: \(count1), Counter 2: \(count2)")

        XCTAssertEqual(count1, 1, "Handler 1 should have been called once")
        XCTAssertEqual(count2, 1, "Handler 2 should have been called once")

        // Clean up (matching Rust exactly)
        try await node.unsubscribeFromEvents(subscriptionId: subId1)
        try await node.unsubscribeFromEvents(subscriptionId: subId2)

        await node.stop()
    }

    /// Test the exact scenario from the remote test - MathService + external subscription
    /// Mirrors Rust test_math_service_plus_external_subscription exactly
    func testMathServicePlusExternalSubscription() async throws {
        // Create a node with NO networking (matching Rust exactly)
        let config = try await createNodeTestConfig()
        let node = try await Node.new(config: config)

        // Add MathService (this will create its own subscription to math/added) (matching Rust exactly)
        let mathService = TestMathService(name: "math1", path: "math1")
        try await node.addService(mathService)

        // Create an external subscription to the same event BEFORE starting (matching Rust exactly)
        let receivedData = AtomicReference<AnyValue?>(initialValue: nil)
        let receivedDataRef = receivedData

        let subId = try await node.subscribe(
            topic: "math1/math/added",
            options: EventRegistrationOptions(),
            callback: { _, data in
                Task {
                    await receivedDataRef.setValue(data)
                    print("External handler received: \(String(describing: data))")
                }
            }
        )

        print("Created external subscription: \(subId)")

        // Start the node (matching Rust exactly)
        try await node.start()
        print("Node started with MathService")
        try await node.waitForServicesToStart()

        // Call the math operation (which should publish math/added) (matching Rust exactly)
        let params = AnyValue.map([
            "a": AnyValue.primitive(5.0),
            "b": AnyValue.primitive(3.0),
        ])
        let result = try await node.request("math1/add", payload: params)

        let resultValue: Double = try await result.asType()
        XCTAssertEqual(resultValue, 8.0, accuracy: 0.001)
        print("Math operation completed: 5 + 3 = \(resultValue)")

        // Give handlers time to execute (matching Rust exactly)
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Check that the external subscription received the event (matching Rust exactly)
        let received = await receivedData.value
        XCTAssertNotNil(received, "External subscription should have received the math/added event")

        if let data = received {
            let eventValue: Double = try await data.asType()
            XCTAssertEqual(eventValue, 8.0, accuracy: 0.001, "Event data should match the math result")
            print("✅ External subscription received correct data: \(eventValue)")
        }

        // Clean up (matching Rust exactly)
        try await node.unsubscribeFromEvents(subscriptionId: subId)

        await node.stop()
    }

    // MARK: - Helper Classes

    /// AtomicInteger implementation to match Rust AtomicUsize behavior
    /// Used for callback execution tracking in tests
    actor AtomicInteger {
        private var _value: Int

        init(initialValue: Int) {
            _value = initialValue
        }

        var value: Int {
            _value
        }

        func increment() {
            _value += 1
        }
    }

    /// AtomicReference implementation to match Rust Arc<Mutex<T>> behavior
    /// Used for thread-safe data sharing in tests
    actor AtomicReference<T> {
        private var _value: T

        init(initialValue: T) {
            _value = initialValue
        }

        var value: T {
            _value
        }

        func setValue(_ newValue: T) {
            _value = newValue
        }
    }

    /// Test math service for testing purposes
    /// Mirrors the Rust MathService behavior exactly
    private class TestMathService: AbstractService {
        let name: String
        let version: String = "1.0.0"
        let path: String
        let description: String
        var networkId: String?
        var state: ServiceState = .created
        let logger: RunarLogger

        init(name: String, path: String) {
            self.name = name
            self.path = path
            description = "Test math service"
            logger = RunarLogger.root(component: .service)
        }

        func setNetworkId(_ networkId: String) {
            self.networkId = networkId
        }

        func initService(_ context: LifecycleContext) async throws {
            // Register action handlers (matching Rust MathService exactly)
            try await context.nodeDelegate.registerAction(
                networkId: context.networkId,
                servicePath: context.servicePath,
                action: "add",
                handler: { [weak self] payload, requestContext in
                    guard let self else { return AnyValue.null() }
                    return try await handleAdd(requestContext: requestContext, payload: payload)
                }
            )
        }

        func start(_ context: LifecycleContext) async throws {
            // Subscribe to math/added events (matching Rust MathService exactly)
            try await context.nodeDelegate.subscribe(
                topic: "\(context.servicePath)/math/added",
                options: EventRegistrationOptions(),
                callback: { [weak self] eventContext, data in
                    guard let self else { return }
                    try await handleMathAdded(eventContext: eventContext, data: data)
                }
            )
        }

        func stop(_: LifecycleContext) async throws {
            // Stop the service
        }

        private func handleAdd(requestContext: RequestContext, payload: AnyValue?) async throws -> AnyValue {
            guard let payload,
                  let params = try? await payload.asType() as [String: AnyValue],
                  let aValue = params["a"],
                  let bValue = params["b"],
                  let a = try? await aValue.asType() as Double,
                  let b = try? await bValue.asType() as Double
            else {
                throw NodeError.invalidServicePath("Invalid parameters for add operation")
            }

            let result = a + b

            // Publish the result as an event (matching Rust MathService exactly)
            try await requestContext.nodeDelegate.publish(
                topic: "\(requestContext.topicPath.servicePath)/math/added",
                data: AnyValue.primitive(result)
            )

            return AnyValue.primitive(result)
        }

        private func handleMathAdded(eventContext _: EventContext, data: AnyValue?) async throws {
            // Handle the math/added event (matching Rust MathService exactly)
            if let data,
               let value = try? await data.asType() as Double
            {
                print("MathService received math/added event: \(value)")
            }
        }
    }
}
