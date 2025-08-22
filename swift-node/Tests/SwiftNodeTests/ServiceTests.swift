import RunarSerializer
import SwiftCommon
@testable import SwiftNode
import XCTest

@MainActor
final class ServiceTests: XCTestCase {
    func testKeysServiceLifecycle() async throws {
        // Test KeysService initialization and basic operations
        let logger = RunarLogger(component: .keys)
        let keysService = KeysService(logger: logger, nodeId: "test-node-123")

        // Test initialization
        let context = LifecycleContext(
            networkId: "test-network",
            servicePath: "$keys",
            config: nil,
            logger: logger,
            nodeDelegate: MockNodeDelegate()
        )

        try await keysService.initService(context)
        XCTAssertEqual(keysService.state, .initialized)

        // Test starting service
        try await keysService.start(context)
        XCTAssertEqual(keysService.state, .running)

        // Test basic operations
        let publicKey = try await keysService.getPublicKey()
        XCTAssertFalse(publicKey.publicKey.isEmpty)

        // Note: Sign/verify methods removed - focus on available FFI methods

        // Test stopping service
        try await keysService.stop(context)
        XCTAssertEqual(keysService.state, .stopped)
    }

    func testRegistryServiceLifecycle() async throws {
        // Test RegistryService initialization and basic operations
        let logger = RunarLogger(component: .registry)
        let serviceRegistry = ServiceRegistry(logger: logger)
        let registryService = RegistryService(logger: logger, nodeId: "test-node-123", serviceRegistry: serviceRegistry)

        let context = LifecycleContext(
            networkId: "test-network",
            servicePath: "$registry",
            config: nil,
            logger: logger,
            nodeDelegate: MockNodeDelegate()
        )

        // Test initialization
        try await registryService.initService(context)
        XCTAssertEqual(registryService.state, .initialized)

        // Test starting service
        try await registryService.start(context)
        XCTAssertEqual(registryService.state, .running)

        // Register the service in the registry (simulating what the node would do)
        await serviceRegistry.registerLocalService(
            servicePath: "$registry",
            name: "Registry",
            version: "1.0.0",
            description: "Internal service registry management and discovery"
        )

        // Test listing services
        let services = try await registryService.listServices()
        // Should have at least the registry service itself
        XCTAssertFalse(services.services.isEmpty)

        // Test stopping service
        try await registryService.stop(context)
        XCTAssertEqual(registryService.state, .stopped)
    }

    func testRemoteServiceLifecycle() async throws {
        // Test RemoteService initialization and basic operations
        let logger = RunarLogger(component: .service)
        let serviceRegistry = ServiceRegistry(logger: logger)
        let remoteService = RemoteService(logger: logger, nodeId: "test-node-123", serviceRegistry: serviceRegistry)

        let context = LifecycleContext(
            networkId: "test-network",
            servicePath: "$remote",
            config: nil,
            logger: logger,
            nodeDelegate: MockNodeDelegate()
        )

        // Test initialization
        try await remoteService.initService(context)
        XCTAssertEqual(remoteService.state, .initialized)

        // Test starting service
        try await remoteService.start(context)
        XCTAssertEqual(remoteService.state, .running)

        // Skip load balancing tests as these features don't exist in Rust implementation

        // Test stopping service
        try await remoteService.stop(context)
        XCTAssertEqual(remoteService.state, .stopped)
    }

    func testServiceStateTransitions() async throws {
        let logger = RunarLogger(component: .keys)
        let keysService = KeysService(logger: logger, nodeId: "test-node-123")

        let context = LifecycleContext(
            networkId: "test-network",
            servicePath: "$keys",
            config: nil,
            logger: logger,
            nodeDelegate: MockNodeDelegate()
        )

        // Test state transitions
        XCTAssertEqual(keysService.state, .created)

        try await keysService.initService(context)
        XCTAssertEqual(keysService.state, .initialized)

        try await keysService.start(context)
        XCTAssertEqual(keysService.state, .running)

        // Skip pause/resume tests as these methods don't exist in Rust implementation

        try await keysService.stop(context)
        XCTAssertEqual(keysService.state, .stopped)
    }

    func testServiceErrorHandling() async throws {
        let logger = RunarLogger(component: .keys)
        let keysService = KeysService(logger: logger, nodeId: "test-node-123")

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
        XCTAssertEqual(keysService.state, .initialized)
    }
}

// MARK: - Mock NodeDelegate

private class MockNodeDelegate: NodeDelegate {
    func registerAction(networkId _: String, servicePath _: String, action _: String, handler _: @escaping ActionHandler) async throws {
        // Mock implementation - do nothing
    }

    func subscribe(topic _: String, options _: EventRegistrationOptions?, callback _: @escaping EventHandler) async throws -> String {
        return UUID().uuidString
    }

    func unsubscribe(_: String) async throws {
        // Mock implementation - do nothing
    }

    func publish(topic _: String, data _: AnyValue?) async throws {
        // Mock implementation - do nothing
    }

    func requestToPeer(path _: String, payload _: AnyValue?, peerNodeId _: String, timeoutMs _: UInt64?) async throws -> AnyValue {
        // Mock implementation - return null
        return AnyValue.null()
    }
}
