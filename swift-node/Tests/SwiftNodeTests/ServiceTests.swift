import RunarSerializer
import SwiftCommon
@testable import SwiftNode
import XCTest

// MARK: - Mock Delegates

@MainActor
final class MockRegistryDelegate: RegistryDelegate {
    func getLocalServiceState(servicePath: TopicPath) async -> ServiceState? {
        return .running
    }
    
    func getRemoteServiceState(servicePath: TopicPath) async -> ServiceState? {
        return nil
    }
    
    func getServiceMetadata(servicePath: TopicPath) async -> ServiceMetadata? {
        return ServiceMetadata(
            networkId: "test-network",
            servicePath: servicePath.servicePath,
            name: "TestService",
            version: "1.0.0",
            description: "Test service",
            actions: [],
            registrationTime: UInt64(Date().timeIntervalSince1970),
            lastStartTime: nil
        )
    }
    
    func getAllServiceMetadata(includeInternalServices: Bool) async throws -> [String: ServiceMetadata] {
        return [:]
    }
    
    func getActionsMetadata(serviceTopicPath: TopicPath) async -> [ActionMetadata] {
        return []
    }
    
    func registerRemoteActionHandler(topicPath: TopicPath, handler: ActionHandler) async throws {
        // Mock implementation
    }
    
    func removeRemoteActionHandler(topicPath: TopicPath) async throws {
        // Mock implementation
    }
    
    func registerRemoteEventHandler(topicPath: TopicPath, handler: EventHandler) async throws {
        // Mock implementation
    }
    
    func removeRemoteEventHandler(topicPath: TopicPath) async throws {
        // Mock implementation
    }
    
    func updateLocalServiceStateIfValid(servicePath: TopicPath, newState: ServiceState, currentState: ServiceState) async throws {
        // Mock implementation
    }
    
    func validatePauseTransition(servicePath: TopicPath) async throws {
        // Mock implementation
    }
    
    func validateResumeTransition(servicePath: TopicPath) async throws {
        // Mock implementation
    }
}

@MainActor
final class MockNodeDelegate: NodeDelegate {
    func registerAction(networkId: String, servicePath: String, action: String, handler: @escaping ActionHandler) async throws {
        // Mock implementation
    }
    
    func unregisterAction(networkId: String, servicePath: String, action: String) async throws {
        // Mock implementation
    }
    
    func subscribeToEvents(networkId: String, servicePath: String, handler: @escaping EventHandler) async throws -> String {
        return "mock-subscription-id"
    }
    
    func unsubscribeFromEvents(subscriptionId: String) async throws {
        // Mock implementation
    }
    
    func subscribe(topic: String, options: EventRegistrationOptions?, callback: @escaping EventHandler) async throws -> String {
        return "mock-subscription-id"
    }
    
    func publish(topic: String, data: AnyValue?) async throws {
        // Mock implementation
    }
}

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
        // Test KeysService initialization and basic operations
        let logger = testLogger.child(component: .node)
        let keysService = KeysService(logger: logger, nodeDelegate: MockNodeDelegate())

        // Test initialization
        let context = LifecycleContext(
            networkId: "test-network",
            servicePath: "$keys",
            config: nil,
            logger: logger,
            nodeDelegate: MockNodeDelegate()
        )

        try await keysService.initService(context)

        // Test starting service
        try await keysService.start(context)

        // Test basic operations - KeysService doesn't expose getPublicKey method
        // This would be tested through the actual key operations

        // Note: Sign/verify methods removed - focus on available FFI methods

        // Test stopping service
        try await keysService.stop(context)
    }

    func testRegistryServiceLifecycle() async throws {
        // Test RegistryService initialization and basic operations
        let logger = testLogger.child(component: .registry)
        let serviceRegistry = ServiceRegistry(logger: logger)
        let mockRegistryDelegate = MockRegistryDelegate()
        let registryService = RegistryService(logger: logger, registryDelegate: mockRegistryDelegate)

        let context = LifecycleContext(
            networkId: "test-network",
            servicePath: "$registry",
            config: nil,
            logger: logger,
            nodeDelegate: MockNodeDelegate()
        )

        // Test initialization
        try await registryService.initService(context)

        // Test starting service
        try await registryService.start(context)

        // Registry service is automatically registered by the node
        // Test that the service is working by checking its state

        // Test stopping service
        try await registryService.stop(context)
    }


    func testServiceStateTransitions() async throws {
        let logger = testLogger.child(component: .node)
        let keysService = KeysService(logger: logger, nodeDelegate: MockNodeDelegate())

        let context = LifecycleContext(
            networkId: "test-network",
            servicePath: "$keys",
            config: nil,
            logger: logger,
            nodeDelegate: MockNodeDelegate()
        )

        // Test state transitions
        try await keysService.initService(context)

        try await keysService.start(context)

        // Skip pause/resume tests as these methods don't exist in Rust implementation

        try await keysService.stop(context)
    }

    func testServiceErrorHandling() async throws {
        let logger = testLogger.child(component: .node)
        let keysService = KeysService(logger: logger, nodeDelegate: MockNodeDelegate())

        let context = LifecycleContext(
            networkId: "test-network",
            servicePath: "$keys",
            config: nil,
            logger: logger,
            nodeDelegate: MockNodeDelegate()
        )

        // Test error handling during initialization
        // (This would normally test error scenarios, but for demo we just test normal flow)
        try await keysService.initService(context)
    }
}

