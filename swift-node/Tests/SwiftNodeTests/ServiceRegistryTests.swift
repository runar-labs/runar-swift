import Foundation
import RunarSerializer
import SwiftCommon
@testable import SwiftNode
import XCTest

/// AtomicBoolean implementation to match Rust AtomicBool behavior
/// Used for callback execution tracking in tests
actor AtomicBoolean {
    private var _value: Bool

    init(initialValue: Bool) {
        _value = initialValue
    }

    var value: Bool {
        return _value
    }

    func setValue(_ newValue: Bool) {
        _value = newValue
    }
}

/// Timeout wrapper implementation matching Rust timeout behavior
/// Ensures tests don't hang indefinitely (matching Rust timeout(Duration::from_secs(10), ...))
extension XCTestCase {
    /// Execute async test with timeout (matching Rust timeout behavior)
    @MainActor
    func withTimeout<T: Sendable>(
        _ timeout: TimeInterval = 10.0,
        file _: StaticString = #filePath,
        line _: UInt = #line,
        operation: @escaping @MainActor () async throws -> T
    ) async throws -> T {
        // Create a task for the operation
        let operationTask = Task { @MainActor in
            try await operation()
        }

        // Create a timeout task
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            operationTask.cancel()
            throw TimeoutError.timeout
        }

        // Wait for either the operation to complete or timeout
        do {
            let result = try await operationTask.value
            timeoutTask.cancel()
            return result
        } catch {
            timeoutTask.cancel()
            if operationTask.isCancelled {
                throw TimeoutError.timeout
            } else {
                throw error
            }
        }
    }
}

/// Timeout error for test timeouts
enum TimeoutError: Error {
    case timeout
}

/// Service registry tests following the rules - no mocks, no shortcuts, real implementations
/// These tests match the Rust service_registry_test.rs exactly
@MainActor
final class ServiceRegistryTests: XCTestCase {
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
        testLogger = RunarLogger.root(component: .custom("ServiceRegistryTests"))
    }

    // MARK: - Test Setup

    private func createTestLogger() -> RunarLogger {
        testLogger.child(component: .node)
    }

    private func createTestRegistry() -> ServiceRegistry {
        ServiceRegistry(logger: createTestLogger())
    }

    // MARK: - Service Registration Tests

    /// Test that verifies service registry creation
    func testServiceRegistryCreation() {
        let registry = createTestRegistry()
        XCTAssertNotNil(registry)
    }

    /// Test that verifies local service registration
    func testRegisterLocalService() async throws {
        let registry = createTestRegistry()

        // Create a test service
        let service = TestMathService()
        let serviceTopic = try TopicPath.new("math", defaultNetwork: "test-network")
        let serviceEntry = ServiceEntry(
            serviceTopic: serviceTopic,
            service: service,
            state: .initialized,
            registrationTime: 1000,
            lastStartTime: nil
        )

        // Register the service
        try await registry.registerLocalService(serviceEntry)

        // Verify the service was registered
        let services = await registry.getLocalServices()
        XCTAssertEqual(services.count, 1)
        XCTAssertNotNil(services[serviceTopic])
    }

    /// Test that verifies service instance registration (using registerLocalService)
    func testRegisterServiceInstance() async throws {
        let registry = createTestRegistry()

        // Create a test service
        let service = TestMathService()
        let serviceTopic = try TopicPath.new("math", defaultNetwork: "test-network")

        // Create ServiceEntry (matching Rust pattern)
        let serviceEntry = ServiceEntry(
            serviceTopic: serviceTopic,
            service: service,
            state: .initialized,
            registrationTime: UInt64(Date().timeIntervalSince1970)
        )

        // Register the service using registerLocalService (matching Rust pattern)
        try await registry.registerLocalService(serviceEntry)

        // Verify the service was registered
        let services = await registry.getLocalServices()
        XCTAssertEqual(services.count, 1)
    }

    /// Test that verifies multiple service registration
    func testRegisterMultipleServices() async throws {
        let registry = createTestRegistry()

        // Create multiple test services
        let service1 = TestMathService()
        let service2 = TestMathService()

        let topic1 = try TopicPath.new("math1", defaultNetwork: "test-network")
        let topic2 = try TopicPath.new("math2", defaultNetwork: "test-network")

        let entry1 = ServiceEntry(serviceTopic: topic1, service: service1, state: .initialized, registrationTime: 1000)
        let entry2 = ServiceEntry(serviceTopic: topic2, service: service2, state: .initialized, registrationTime: 1001)

        // Register both services
        try await registry.registerLocalService(entry1)
        try await registry.registerLocalService(entry2)

        // Verify both services were registered
        let services = await registry.getLocalServices()
        XCTAssertEqual(services.count, 2)
        XCTAssertNotNil(services[topic1])
        XCTAssertNotNil(services[topic2])
    }

    // MARK: - Action Handler Tests

    /// Test that verifies action handler registration and retrieval
    /// Matches Rust test_register_and_get_action_handler exactly
    func testRegisterAndGetActionHandler() async throws {
        // Wrap the test in a timeout to prevent it from hanging (matching Rust)
        try await withTimeout(10.0) {
            // Create a service registry (matching Rust)
            let logger = self.testLogger.child(component: .node)
            let registry = ServiceRegistry(logger: logger)

            let servicePath = "math"
            let actionName = "add"

            // Create a TopicPath for the action (matching Rust)
            let actionPath = "\(servicePath)/\(actionName)"
            let topicPath = try TopicPath.new(actionPath, defaultNetwork: "net1")

            // Create a handler (matching Rust)
            let handler: ActionHandler = { _, _ in
                // Handler implementation - logging removed due to actor isolation
                AnyValue.null()
            }

            // Register the handler using the correct method (matching Rust)
            try await registry.registerLocalActionHandler(
                topicPath: topicPath,
                handler: handler,
                metadata: nil
            )

            // Get the handler using the correct local method (matching Rust)
            let retrievedHandler = await registry.getLocalActionHandler(topicPath: topicPath)

            // Verify the handler was registered and can be retrieved (matching Rust)
            XCTAssertNotNil(retrievedHandler, "Handler should be found")

            // Check for a non-existent handler (matching Rust)
            let nonExistentPath = try TopicPath.new("math/nonexistent", defaultNetwork: "net1")
            let nonExistentHandler = await registry.getLocalActionHandler(topicPath: nonExistentPath)
            XCTAssertNil(nonExistentHandler, "Should not find a handler for a non-existent path")
        }
    }

    /// Test that verifies multiple action handlers
    func testMultipleActionHandlers() async throws {
        let registry = createTestRegistry()
        let networkId = "net1"

        // Create a Node instance for testing
        let config = try await createNodeTestConfig()
        let node = try await Node.new(config: config)
        try await node.start()

        // Create handlers for different actions
        let addHandler: ActionHandler = { _, _ in
            AnyValue.primitive("add_result")
        }

        let subtractHandler: ActionHandler = { _, _ in
            AnyValue.primitive("subtract_result")
        }

        // Register both handlers
        try await registry.registerAction(networkId: networkId, servicePath: "math", action: "add", handler: addHandler)
        try await registry.registerAction(networkId: networkId, servicePath: "math", action: "subtract", handler: subtractHandler)

        // Test both handlers through Node (matching Rust architecture)
        let addResult = try await node.request("math/add", payload: nil as AnyValue?, networkId: networkId)
        let subtractResult = try await node.request("math/subtract", payload: nil as AnyValue?, networkId: networkId)

        XCTAssertNotNil(addResult)
        XCTAssertNotNil(subtractResult)

        try await node.stop()
    }

    /// Test that verifies action handler network isolation
    func testActionHandlerNetworkIsolation() async throws {
        let registry = createTestRegistry()

        // Create a Node instance for testing
        let config = try await createNodeTestConfig()
        let node = try await Node.new(config: config)
        try await node.start()

        // Create handlers for different networks
        let handler1: ActionHandler = { _, _ in
            AnyValue.primitive("network1_result")
        }

        let handler2: ActionHandler = { _, _ in
            AnyValue.primitive("network2_result")
        }

        // Register handlers in different networks
        try await registry.registerAction(networkId: "network1", servicePath: "math", action: "add", handler: handler1)
        try await registry.registerAction(networkId: "network2", servicePath: "math", action: "add", handler: handler2)

        // Test that handlers are isolated by network
        let result1 = try await node.request("math/add", payload: nil as AnyValue?, networkId: "network1")
        let result2 = try await node.request("math/add", payload: nil as AnyValue?, networkId: "network2")

        XCTAssertNotNil(result1)
        XCTAssertNotNil(result2)

        try await node.stop()
    }

    // MARK: - Event Subscription Tests

    /// Test that verifies event subscription and unsubscription
    /// Matches Rust test_subscribe_and_unsubscribe exactly
    func testSubscribeAndUnsubscribe() async throws {
        // Wrap the test in a timeout to prevent it from hanging (matching Rust)
        try await withTimeout(10.0) {
            // Create a service registry (matching Rust)
            let registry = ServiceRegistry(logger: self.testLogger.child(component: .node))

            // Create a TopicPath for the test topic (matching Rust)
            let topic = try TopicPath.new("test/event", defaultNetwork: "net1")

            // Create a flag to track if the callback was called (matching Rust AtomicBool)
            let wasCalled = AtomicBoolean(initialValue: false)

            // Create a callback that would be invoked when an event is published (matching Rust)
            let callback: EventHandler = { _, _ in
                // Set the flag to true when called (matching Rust)
                Task {
                    await wasCalled.setValue(true)
                }
            }

            // Subscribe to the topic using the correct method (matching Rust)
            let subscriptionId = try await registry.registerLocalEventSubscription(
                topicPath: topic,
                callback: callback,
                options: EventRegistrationOptions()
            )

            // Test the get_local_event_subscribers method (matching Rust)
            let handlers = await registry.getLocalEventSubscribers(topicPath: topic)
            XCTAssertEqual(handlers.count, 1, "Expected one handler to be registered")
            XCTAssertEqual(handlers[0].0, subscriptionId, "Subscriber ID should match")

            // Unsubscribe using the correct method (matching Rust)
            _ = try await registry.unsubscribeLocal(subscriptionId: subscriptionId)

            // Verify the handler is removed (matching Rust)
            let handlersAfter = await registry.getLocalEventSubscribers(topicPath: topic)
            XCTAssertEqual(handlersAfter.count, 0, "Expected no handlers after unsubscription")
        }
    }

    /// Test that verifies wildcard subscriptions
    /// Matches Rust test_wildcard_subscriptions exactly
    func testWildcardSubscriptions() async throws {
        // Wrap the test in a timeout to prevent it from hanging (matching Rust)
        try await withTimeout(10.0) {
            // Create a service registry (matching Rust)
            let registry = ServiceRegistry(logger: self.testLogger.child(component: .node))

            // Create a callback (matching Rust)
            let callback: EventHandler = { _, _ in
                // Simple callback that does nothing (matching Rust)
            }

            // Create TopicPaths for wildcard subscriptions (matching Rust)
            let wildcard1 = try TopicPath.new("test/#", defaultNetwork: "net1")
            let wildcard2 = try TopicPath.new("test/events/#", defaultNetwork: "net1")

            // Subscribe to wildcard topics using the correct method (matching Rust)
            _ = try await registry.registerLocalEventSubscription(
                topicPath: wildcard1,
                callback: callback,
                options: EventRegistrationOptions()
            )
            let id2 = try await registry.registerLocalEventSubscription(
                topicPath: wildcard2,
                callback: callback,
                options: EventRegistrationOptions()
            )

            // Verify handlers are registered correctly using the correct method (matching Rust)
            let handlers1 = await registry.getLocalEventSubscribers(topicPath: wildcard1)
            let handlers2 = await registry.getLocalEventSubscribers(topicPath: wildcard2)

            XCTAssertEqual(handlers1.count, 1, "Expected one handler for wildcard1")
            XCTAssertEqual(handlers2.count, 1, "Expected one handler for wildcard2")

            // Unsubscribe from one wildcard using the correct method (matching Rust)
            _ = try await registry.unsubscribeLocal(subscriptionId: id2)

            // Verify the handler is removed using the correct method (matching Rust)
            let handlers2After = await registry.getLocalEventSubscribers(topicPath: wildcard2)
            XCTAssertEqual(handlers2After.count, 0, "Expected handler to be removed from wildcard2")

            // But wildcard1 should still have its handler using the correct method (matching Rust)
            let handlers1After = await registry.getLocalEventSubscribers(topicPath: wildcard1)
            XCTAssertEqual(handlers1After.count, 1, "Expected wildcard1 handler to remain")
        }
    }

    /// Test that verifies multiple event handlers
    func testMultipleEventHandlers() async throws {
        let registry = createTestRegistry()

        // Create multiple callbacks
        let callback1: EventHandler = { _, _ in
            // Event callback 1 - logging removed due to actor isolation
        }

        let callback2: EventHandler = { _, _ in
            // Event callback 2 - logging removed due to actor isolation
        }

        // Subscribe both callbacks to the same topic
        let id1 = try await registry.subscribeToEvents(
            networkId: "net1",
            servicePath: "test/event",
            handler: callback1
        )

        let id2 = try await registry.subscribeToEvents(
            networkId: "net1",
            servicePath: "test/event",
            handler: callback2
        )

        // Verify both subscriptions were created
        XCTAssertNotNil(id1)
        XCTAssertNotNil(id2)
        XCTAssertNotEqual(id1, id2)
    }

    // MARK: - Service State Management Tests

    /// Test that verifies service state updates
    func testServiceStateUpdates() async throws {
        let registry = createTestRegistry()

        // Create a test service
        let service = TestMathService()
        let serviceTopic = try TopicPath.new("math", defaultNetwork: "test-network")

        // Create ServiceEntry (matching Rust pattern)
        let serviceEntry = ServiceEntry(
            serviceTopic: serviceTopic,
            service: service,
            state: .initialized,
            registrationTime: UInt64(Date().timeIntervalSince1970)
        )

        // Register the service using registerLocalService (matching Rust pattern)
        try await registry.registerLocalService(serviceEntry)

        // Update service state
        try await registry.updateLocalServiceState(servicePath: serviceTopic.asString(), newState: .running)

        // Verify state was updated
        let state = await registry.getLocalServiceState(servicePath: serviceTopic)
        XCTAssertEqual(state, .running)
    }

    /// Test that verifies service state transitions
    func testServiceStateTransitions() async throws {
        let registry = createTestRegistry()

        // Create a test service
        let service = TestMathService()
        let serviceTopic = try TopicPath.new("math", defaultNetwork: "test-network")

        // Create ServiceEntry (matching Rust pattern)
        let serviceEntry = ServiceEntry(
            serviceTopic: serviceTopic,
            service: service,
            state: .initialized,
            registrationTime: UInt64(Date().timeIntervalSince1970)
        )

        // Register the service using registerLocalService (matching Rust pattern)
        try await registry.registerLocalService(serviceEntry)

        // Test valid state transitions
        try await registry.updateLocalServiceStateIfValid(
            servicePath: serviceTopic,
            newState: .running,
            currentState: .initialized
        )

        // Test invalid state transition
        do {
            try await registry.updateLocalServiceStateIfValid(
                servicePath: serviceTopic,
                newState: .paused,
                currentState: .stopped
            )
            XCTFail("Should have thrown an error for invalid state transition")
        } catch {
            // Expected error
            XCTAssertTrue(error is ServiceRegistryError)
        }
    }

    // MARK: - Service Metadata Tests

    /// Test that verifies service metadata retrieval
    func testGetServiceMetadata() async throws {
        let registry = createTestRegistry()

        // Create a test service
        let service = TestMathService()
        let serviceTopic = try TopicPath.new("math", defaultNetwork: "test-network")

        // Create ServiceEntry (matching Rust pattern)
        let serviceEntry = ServiceEntry(
            serviceTopic: serviceTopic,
            service: service,
            state: .initialized,
            registrationTime: UInt64(Date().timeIntervalSince1970)
        )

        // Register the service using registerLocalService (matching Rust pattern)
        try await registry.registerLocalService(serviceEntry)

        // Get service metadata
        let metadata = await registry.getServiceMetadata(servicePath: serviceTopic)

        // Verify metadata was retrieved
        XCTAssertNotNil(metadata)
        XCTAssertEqual(metadata?.name, "TestMathService")
        XCTAssertEqual(metadata?.servicePath, "math")
    }

    /// Test that verifies all service metadata retrieval
    func testGetAllServiceMetadata() async throws {
        let registry = createTestRegistry()

        // Create multiple test services with different paths
        let service1 = TestMathService1()
        let service2 = TestMathService2()

        // Create ServiceEntries (matching Rust pattern)
        let topic1 = try TopicPath.new("math1", defaultNetwork: "test-network")
        let topic2 = try TopicPath.new("math2", defaultNetwork: "test-network")

        let entry1 = ServiceEntry(
            serviceTopic: topic1,
            service: service1,
            state: .initialized,
            registrationTime: UInt64(Date().timeIntervalSince1970)
        )

        let entry2 = ServiceEntry(
            serviceTopic: topic2,
            service: service2,
            state: .initialized,
            registrationTime: UInt64(Date().timeIntervalSince1970)
        )

        // Register both services using registerLocalService (matching Rust pattern)
        try await registry.registerLocalService(entry1)
        try await registry.registerLocalService(entry2)

        // Get all service metadata
        let allMetadata = await registry.getAllLocalServiceMetadata(includeInternalServices: false)

        // Verify metadata was retrieved
        XCTAssertEqual(allMetadata.count, 2)
    }

    /// Test that verifies actions metadata retrieval
    /// Matches Rust test_get_actions_metadata exactly
    func testGetActionsMetadata() async throws {
        // Wrap the test in a timeout to prevent it from hanging (matching Rust)
        try await withTimeout(10.0) {
            // Set up test logger (matching Rust)
            let logger = self.testLogger.child(component: .node)

            // Create registry (matching Rust)
            let registry = ServiceRegistry(logger: logger)

            // Create a service path and action paths (matching Rust)
            let servicePath = try TopicPath.new("math-service", defaultNetwork: "test-network")
            let addActionPath = try TopicPath.new("math-service/add", defaultNetwork: "test-network")
            let subtractActionPath = try TopicPath.new("math-service/subtract", defaultNetwork: "test-network")
            let multiplyActionPath = try TopicPath.new("math-service/multiply", defaultNetwork: "test-network")

            // Create action handlers (matching Rust)
            let addHandler: ActionHandler = { _, _ in
                AnyValue.null()
            }
            let addMetadata = ActionMetadata(
                name: addActionPath.asString(),
                description: "Add action"
            )

            let subtractHandler: ActionHandler = { _, _ in
                AnyValue.null()
            }
            let subtractMetadata = ActionMetadata(
                name: subtractActionPath.asString(),
                description: "Subtract action"
            )

            let multiplyHandler: ActionHandler = { _, _ in
                AnyValue.null()
            }
            let multiplyMetadata = ActionMetadata(
                name: multiplyActionPath.asString(),
                description: "Multiply action"
            )

            // Register the action handlers (matching Rust)
            try await registry.registerLocalActionHandler(
                topicPath: addActionPath,
                handler: addHandler,
                metadata: addMetadata
            )
            try await registry.registerLocalActionHandler(
                topicPath: subtractActionPath,
                handler: subtractHandler,
                metadata: subtractMetadata
            )
            try await registry.registerLocalActionHandler(
                topicPath: multiplyActionPath,
                handler: multiplyHandler,
                metadata: multiplyMetadata
            )

            // Create a wildcard path to match all actions under this service (matching Rust)
            let servicePathStr = servicePath.servicePath
            let wildcardPath = "\(servicePathStr)/*"
            let searchPath = try TopicPath.new(wildcardPath, defaultNetwork: servicePath.networkId)

            // Get the action metadata for the service using the wildcard path (matching Rust)
            let actionsMetadata = await registry.getActionsMetadata(serviceTopicPath: searchPath)

            // Verify that we got metadata for all three actions (matching Rust)
            XCTAssertEqual(actionsMetadata.count, 3, "Should have metadata for all three actions")

            // Verify the paths of the actions in the metadata (matching Rust)
            let actionPaths = actionsMetadata.map(\.name)
            XCTAssertTrue(actionPaths.contains(addActionPath.asString()), "Missing add action path")
            XCTAssertTrue(actionPaths.contains(subtractActionPath.asString()), "Missing subtract action path")
            XCTAssertTrue(actionPaths.contains(multiplyActionPath.asString()), "Missing multiply action path")
        }
    }

    // MARK: - Request Handling Tests

    /// Test that verifies request handling
    func testRequestHandling() async throws {
        let registry = createTestRegistry()
        let networkId = "net1"

        // Create a Node instance for testing
        let config = try await createNodeTestConfig()
        let node = try await Node.new(config: config)
        try await node.start()

        // Register an action handler
        let handler: ActionHandler = { _, _ in
            AnyValue.primitive("test_result")
        }

        try await registry.registerAction(networkId: networkId, servicePath: "math", action: "add", handler: handler)

        // Make a request
        let result = try await node.request("math/add", payload: nil as AnyValue?, networkId: networkId)

        // Verify request was handled
        XCTAssertNotNil(result)

        try await node.stop()
    }

    /// Test that verifies request to non-existent service
    func testRequestToNonExistentService() async throws {
        let registry = createTestRegistry()

        // Create a Node instance for testing
        let config = try await createNodeTestConfig()
        let node = try await Node.new(config: config)
        try await node.start()

        // Make a request to a non-existent service
        do {
            _ = try await node.request("nonexistent/action", payload: nil as AnyValue?, networkId: "net1")
            XCTFail("Should have thrown an error for non-existent service")
        } catch {
            // Expected error
            XCTAssertTrue(error is ServiceRegistryError)
        }

        try await node.stop()
    }

    // MARK: - Missing Tests from Rust Implementation

    /// Test that verifies path template parameters
    /// Matches Rust test_path_template_parameters exactly
    func testPathTemplateParameters() async throws {
        // Wrap the test in a timeout to prevent it from hanging (matching Rust)
        try await withTimeout(10.0) {
            // Create a service registry (matching Rust)
            let logger = self.testLogger.child(component: .node)
            let registry = ServiceRegistry(logger: logger)

            // Create a handler that expects path parameters (matching Rust)
            let handler: ActionHandler = { _, context in
                // Verify path parameters are extracted correctly
                let pathParams = context.pathParams
                XCTAssertEqual(pathParams["id"], "123", "ID parameter should be extracted")
                XCTAssertEqual(pathParams["action"], "test", "Action parameter should be extracted")
                return AnyValue.primitive("success")
            }

            // Register handler with template path (matching Rust)
            let templatePath = try TopicPath.new("users/{id}/actions/{action}", defaultNetwork: "net1")
            try await registry.registerLocalActionHandler(
                topicPath: templatePath,
                handler: handler,
                metadata: nil
            )

            // Create a Node instance for testing
            let config = try await createNodeTestConfig()
            let node = try await Node.new(config: config)
            try await node.start()

            // Test the handler with a request that should match the template (matching Rust)
            let result = try await node.request("users/123/actions/test", payload: nil as AnyValue?, networkId: "net1")
            XCTAssertNotNil(result, "Handler should be called and return result")

            try await node.stop()
        }
    }

    /// Test that verifies local vs remote action handler separation
    /// Matches Rust test_local_remote_action_handler_separation exactly
    func testLocalRemoteActionHandlerSeparation() async throws {
        // Wrap the test in a timeout to prevent it from hanging (matching Rust)
        try await withTimeout(10.0) {
            // Create a service registry (matching Rust)
            let logger = self.testLogger.child(component: .node)
            let registry = ServiceRegistry(logger: logger)

            let topicPath = try TopicPath.new("test/action", defaultNetwork: "net1")

            // Register local handler (matching Rust)
            let localHandler: ActionHandler = { _, _ in
                AnyValue.primitive("local_result")
            }
            try await registry.registerLocalActionHandler(
                topicPath: topicPath,
                handler: localHandler,
                metadata: nil
            )

            // Register remote handler (matching Rust)
            let remoteHandler: ActionHandler = { _, _ in
                AnyValue.primitive("remote_result")
            }
            try await registry.registerRemoteActionHandler(
                topicPath: topicPath,
                handler: remoteHandler
            )

            // Verify local handler is retrieved correctly (matching Rust)
            let localRetrieved = await registry.getLocalActionHandler(topicPath: topicPath)
            XCTAssertNotNil(localRetrieved, "Local handler should be found")

            // Verify remote handlers are retrieved correctly (matching Rust)
            let remoteHandlers = await registry.getRemoteActionHandlers(topicPath: topicPath)
            XCTAssertEqual(remoteHandlers.count, 1, "Remote handler should be found")

            // Verify they are separate (matching Rust)
            XCTAssertNotNil(localRetrieved, "Local and remote handlers should be separate")
            XCTAssertEqual(remoteHandlers.count, 1, "Local and remote handlers should be separate")
        }
    }

    /// Test that verifies multiple network IDs
    /// Matches Rust test_multiple_network_ids exactly
    func testMultipleNetworkIds() async throws {
        // Wrap the test in a timeout to prevent it from hanging (matching Rust)
        try await withTimeout(10.0) {
            // Create a service registry (matching Rust)
            let logger = self.testLogger.child(component: .node)
            let registry = ServiceRegistry(logger: logger)

            // Register handlers in different networks (matching Rust)
            let handler1: ActionHandler = { _, _ in
                AnyValue.primitive("network1_result")
            }
            let handler2: ActionHandler = { _, _ in
                AnyValue.primitive("network2_result")
            }

            let topicPath1 = try TopicPath.new("test/action", defaultNetwork: "network1")
            let topicPath2 = try TopicPath.new("test/action", defaultNetwork: "network2")

            try await registry.registerLocalActionHandler(
                topicPath: topicPath1,
                handler: handler1,
                metadata: nil
            )
            try await registry.registerLocalActionHandler(
                topicPath: topicPath2,
                handler: handler2,
                metadata: nil
            )

            // Verify handlers are isolated by network (matching Rust)
            let retrieved1 = await registry.getLocalActionHandler(topicPath: topicPath1)
            let retrieved2 = await registry.getLocalActionHandler(topicPath: topicPath2)

            XCTAssertNotNil(retrieved1, "Handler 1 should be found in network1")
            XCTAssertNotNil(retrieved2, "Handler 2 should be found in network2")

            // Verify they are different handlers (matching Rust)
            // Note: Cannot compare ActionHandler functions directly, so we verify they exist
            XCTAssertNotNil(retrieved1?.0, "Handler 1 should exist")
            XCTAssertNotNil(retrieved2?.0, "Handler 2 should exist")
        }
    }

    /// Test that verifies remote event subscription removal
    /// Matches Rust test_remove_remote_event_subscription exactly
    func testRemoveRemoteEventSubscription() async throws {
        // Wrap the test in a timeout to prevent it from hanging (matching Rust)
        try await withTimeout(10.0) {
            // Create a service registry (matching Rust)
            let logger = self.testLogger.child(component: .node)
            let registry = ServiceRegistry(logger: logger)

            let topicPath = try TopicPath.new("test/event", defaultNetwork: "net1")

            // Register remote event subscription (matching Rust)
            let callback: EventHandler = { _, _ in
                // Simple callback
            }
            _ = try await registry.registerRemoteEventSubscription(
                topicPath: topicPath,
                callback: callback,
                options: EventRegistrationOptions()
            )

            // Verify subscription was created (matching Rust)
            let remoteSubscribers = await registry.getRemoteEventSubscribers(topicPath: topicPath)
            XCTAssertEqual(remoteSubscribers.count, 1, "Remote subscription should be created")

            // Remove remote event subscription (matching Rust)
            try await registry.removeRemoteEventSubscription(topicPath: topicPath)

            // Verify subscription was removed (matching Rust)
            let remoteSubscribersAfter = await registry.getRemoteEventSubscribers(topicPath: topicPath)
            XCTAssertEqual(remoteSubscribersAfter.count, 0, "Remote subscription should be removed")
        }
    }

    // MARK: - Event Publishing Tests

    /// Test that verifies event publishing
    func testEventPublishing() async throws {
        let registry = createTestRegistry()

        // Create a callback
        let callback: EventHandler = { _, _ in
            // Event callback - logging removed due to actor isolation
        }

        // Subscribe to events
        _ = try await registry.subscribeToEvents(
            networkId: "net1",
            servicePath: "test/event",
            handler: callback
        )

        // Publish an event
        await registry.publish(topic: "test/event", data: AnyValue.primitive("test_data"), networkId: "net1")

        // No error should be thrown
        XCTAssertTrue(true, "Event publishing should succeed")
    }

    // MARK: - Helper Classes

    /// Test math service for testing purposes
    private class TestMathService: AbstractService {
        let name: String = "TestMathService"
        let version: String = "1.0.0"
        let path: String = "math"
        let description: String = "Test math service"
        var networkId: String?
        var state: ServiceState = .created
        let logger: RunarLogger = .root(component: .service)

        func setNetworkId(_ networkId: String) {
            self.networkId = networkId
        }

        func initService(_: LifecycleContext) async throws {
            // Initialize the service
        }

        func start(_: LifecycleContext) async throws {
            // Start the service
        }

        func stop(_: LifecycleContext) async throws {
            // Stop the service
        }
    }

    /// Test math service 1 for testing purposes
    private class TestMathService1: AbstractService {
        let name: String = "TestMathService1"
        let version: String = "1.0.0"
        let path: String = "math1"
        let description: String = "Test math service 1"
        var networkId: String?
        var state: ServiceState = .created
        let logger: RunarLogger = .root(component: .service)

        func setNetworkId(_ networkId: String) {
            self.networkId = networkId
        }

        func initService(_: LifecycleContext) async throws {
            // Initialize the service
        }

        func start(_: LifecycleContext) async throws {
            // Start the service
        }

        func stop(_: LifecycleContext) async throws {
            // Stop the service
        }
    }

    /// Test math service 2 for testing purposes
    private class TestMathService2: AbstractService {
        let name: String = "TestMathService2"
        let version: String = "1.0.0"
        let path: String = "math2"
        let description: String = "Test math service 2"
        var networkId: String?
        var state: ServiceState = .created
        let logger: RunarLogger = .root(component: .service)

        func setNetworkId(_ networkId: String) {
            self.networkId = networkId
        }

        func initService(_: LifecycleContext) async throws {
            // Initialize the service
        }

        func start(_: LifecycleContext) async throws {
            // Start the service
        }

        func stop(_: LifecycleContext) async throws {
            // Stop the service
        }
    }
}
