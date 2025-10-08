import XCTest
import SwiftNode
import SwiftCommon
import RunarSerializer
import SwiftFFI
import CRunarFFI

@testable import SwiftNode
@testable import SwiftFFI

/// Test for RemoteService.createFromCapabilities method
/// This test verifies that the method works exactly like the Rust implementation
final class RemoteServiceCreateFromCapabilitiesTest: XCTestCase {
    
    private var logger: RunarLogger!
    private var mockKeystore: MockCommonKeyManager!
    private var mockTransport: MockNodeTransport!
    private var labelResolverConfig: LabelResolverConfig!
    private var labelResolverCache: ResolverCache!
    
    override func setUp() async throws {
        logger = RunarLogger.root(component: .custom("RemoteServiceCreateFromCapabilitiesTest"))
        mockKeystore = MockCommonKeyManager()
        mockTransport = MockNodeTransport()
        labelResolverConfig = LabelResolverConfig(labelMappings: [:])
        labelResolverCache = ResolverCache()
    }
    
    override func tearDown() async throws {
        logger = nil
        mockKeystore = nil
        mockTransport = nil
        labelResolverConfig = nil
        labelResolverCache = nil
    }
    
    /// Test creating RemoteServices from valid service metadata
    @MainActor
    func testCreateFromCapabilitiesWithValidServices() async throws {
        // Arrange: Create test service metadata
        let actionMetadata1 = ActionMetadata(
            name: "add",
            description: "Add two numbers",
            inputSchema: nil,
            outputSchema: nil
        )
        
        let actionMetadata2 = ActionMetadata(
            name: "multiply",
            description: "Multiply two numbers",
            inputSchema: nil,
            outputSchema: nil
        )
        
        let serviceMetadata1 = ServiceMetadata(
            networkId: "test-network",
            servicePath: "math1",
            name: "MathService1",
            version: "1.0.0",
            description: "Mathematical operations service 1",
            actions: [actionMetadata1],
            registrationTime: UInt64(Date().timeIntervalSince1970),
            lastStartTime: nil
        )
        
        let serviceMetadata2 = ServiceMetadata(
            networkId: "test-network",
            servicePath: "math2",
            name: "MathService2",
            version: "2.0.0",
            description: "Mathematical operations service 2",
            actions: [actionMetadata2],
            registrationTime: UInt64(Date().timeIntervalSince1970),
            lastStartTime: nil
        )
        
        let config = CreateRemoteServicesConfig(
            services: [serviceMetadata1, serviceMetadata2],
            peerNodeId: "remote-peer-123",
            requestTimeoutMs: 5000
        )
        
        let dependencies = RemoteServiceDependencies(
            networkTransport: mockTransport,
            localNodeId: "local-node-456",
            logger: logger.child(component: .network),
            keystore: mockKeystore,
            labelResolverConfig: labelResolverConfig,
            labelResolverCache: labelResolverCache
        )
        
        // Act: Create RemoteServices from capabilities
        let remoteServices = try await RemoteService.createFromCapabilities(
            config: config,
            dependencies: dependencies
        )
        
        // Assert: Verify correct number of services created
        XCTAssertEqual(remoteServices.count, 2, "Should create exactly 2 RemoteService instances")
        
        // Verify first service
        let service1 = remoteServices[0]
        XCTAssertEqual(service1.name, "MathService1", "Service 1 name should match")
        XCTAssertEqual(service1.version, "1.0.0", "Service 1 version should match")
        XCTAssertEqual(service1.description, "Mathematical operations service 1", "Service 1 description should match")
        XCTAssertEqual(service1.peerNodeId, "remote-peer-123", "Service 1 peer node ID should match")
        XCTAssertEqual(service1.getNetworkId(), "test-network", "Service 1 network ID should match")
        
        // Verify second service
        let service2 = remoteServices[1]
        XCTAssertEqual(service2.name, "MathService2", "Service 2 name should match")
        XCTAssertEqual(service2.version, "2.0.0", "Service 2 version should match")
        XCTAssertEqual(service2.description, "Mathematical operations service 2", "Service 2 description should match")
        XCTAssertEqual(service2.peerNodeId, "remote-peer-123", "Service 2 peer node ID should match")
        XCTAssertEqual(service2.getNetworkId(), "test-network", "Service 2 network ID should match")
        
        // Verify actions were added to services
        let service1Actions = await service1.getAvailableActions()
        XCTAssertEqual(service1Actions.count, 1, "Service 1 should have 1 action")
        XCTAssertTrue(service1Actions.contains("add"), "Service 1 should have 'add' action")
        
        let service2Actions = await service2.getAvailableActions()
        XCTAssertEqual(service2Actions.count, 1, "Service 2 should have 1 action")
        XCTAssertTrue(service2Actions.contains("multiply"), "Service 2 should have 'multiply' action")
    }
    
    /// Test handling of invalid service paths (should skip invalid ones)
    @MainActor
    func testCreateFromCapabilitiesWithInvalidServicePath() async throws {
        // Arrange: Create service metadata with invalid path
        let actionMetadata = ActionMetadata(
            name: "test",
            description: "Test action",
            inputSchema: nil,
            outputSchema: nil
        )
        
        let serviceMetadata = ServiceMetadata(
            networkId: "test-network",
            servicePath: "", // Invalid empty path
            name: "InvalidService",
            version: "1.0.0",
            description: "Service with invalid path",
            actions: [actionMetadata],
            registrationTime: UInt64(Date().timeIntervalSince1970),
            lastStartTime: nil
        )
        
        let config = CreateRemoteServicesConfig(
            services: [serviceMetadata],
            peerNodeId: "remote-peer-123",
            requestTimeoutMs: 5000
        )
        
        let dependencies = RemoteServiceDependencies(
            networkTransport: mockTransport,
            localNodeId: "local-node-456",
            logger: logger.child(component: .network),
            keystore: mockKeystore,
            labelResolverConfig: labelResolverConfig,
            labelResolverCache: labelResolverCache
        )
        
        // Act: Create RemoteServices from capabilities
        let remoteServices = try await RemoteService.createFromCapabilities(
            config: config,
            dependencies: dependencies
        )
        
        // Assert: Should skip invalid service and return empty array
        XCTAssertEqual(remoteServices.count, 0, "Should skip invalid service path and return empty array")
    }
    
    /// Test creating services with multiple actions
    @MainActor
    func testCreateFromCapabilitiesWithMultipleActions() async throws {
        // Arrange: Create service with multiple actions
        let addAction = ActionMetadata(
            name: "add",
            description: "Add two numbers",
            inputSchema: nil,
            outputSchema: nil
        )
        
        let subtractAction = ActionMetadata(
            name: "subtract",
            description: "Subtract two numbers",
            inputSchema: nil,
            outputSchema: nil
        )
        
        let multiplyAction = ActionMetadata(
            name: "multiply",
            description: "Multiply two numbers",
            inputSchema: nil,
            outputSchema: nil
        )
        
        let serviceMetadata = ServiceMetadata(
            networkId: "test-network",
            servicePath: "calculator",
            name: "CalculatorService",
            version: "1.0.0",
            description: "Complete calculator service",
            actions: [addAction, subtractAction, multiplyAction],
            registrationTime: UInt64(Date().timeIntervalSince1970),
            lastStartTime: nil
        )
        
        let config = CreateRemoteServicesConfig(
            services: [serviceMetadata],
            peerNodeId: "remote-peer-123",
            requestTimeoutMs: 5000
        )
        
        let dependencies = RemoteServiceDependencies(
            networkTransport: mockTransport,
            localNodeId: "local-node-456",
            logger: logger.child(component: .network),
            keystore: mockKeystore,
            labelResolverConfig: labelResolverConfig,
            labelResolverCache: labelResolverCache
        )
        
        // Act: Create RemoteServices from capabilities
        let remoteServices = try await RemoteService.createFromCapabilities(
            config: config,
            dependencies: dependencies
        )
        
        // Assert: Should create one service with all actions
        XCTAssertEqual(remoteServices.count, 1, "Should create exactly 1 RemoteService instance")
        
        let service = remoteServices[0]
        XCTAssertEqual(service.name, "CalculatorService", "Service name should match")
        
        let actions = await service.getAvailableActions()
        XCTAssertEqual(actions.count, 3, "Service should have 3 actions")
        XCTAssertTrue(actions.contains("add"), "Service should have 'add' action")
        XCTAssertTrue(actions.contains("subtract"), "Service should have 'subtract' action")
        XCTAssertTrue(actions.contains("multiply"), "Service should have 'multiply' action")
    }
    
    /// Test creating services with mixed valid and invalid paths
    @MainActor
    func testCreateFromCapabilitiesWithMixedValidAndInvalidPaths() async throws {
        // Arrange: Create mix of valid and invalid service metadata
        let validAction = ActionMetadata(
            name: "valid",
            description: "Valid action",
            inputSchema: nil,
            outputSchema: nil
        )
        
        let invalidAction = ActionMetadata(
            name: "invalid",
            description: "Invalid action",
            inputSchema: nil,
            outputSchema: nil
        )
        
        let validService = ServiceMetadata(
            networkId: "test-network",
            servicePath: "valid-service",
            name: "ValidService",
            version: "1.0.0",
            description: "Valid service",
            actions: [validAction],
            registrationTime: UInt64(Date().timeIntervalSince1970),
            lastStartTime: nil
        )
        
        let invalidService = ServiceMetadata(
            networkId: "test-network",
            servicePath: "", // Invalid empty path
            name: "InvalidService",
            version: "1.0.0",
            description: "Invalid service",
            actions: [invalidAction],
            registrationTime: UInt64(Date().timeIntervalSince1970),
            lastStartTime: nil
        )
        
        let config = CreateRemoteServicesConfig(
            services: [validService, invalidService],
            peerNodeId: "remote-peer-123",
            requestTimeoutMs: 5000
        )
        
        let dependencies = RemoteServiceDependencies(
            networkTransport: mockTransport,
            localNodeId: "local-node-456",
            logger: logger.child(component: .network),
            keystore: mockKeystore,
            labelResolverConfig: labelResolverConfig,
            labelResolverCache: labelResolverCache
        )
        
        // Act: Create RemoteServices from capabilities
        let remoteServices = try await RemoteService.createFromCapabilities(
            config: config,
            dependencies: dependencies
        )
        
        // Assert: Should create only the valid service
        XCTAssertEqual(remoteServices.count, 1, "Should create only 1 RemoteService instance (skip invalid)")
        
        let service = remoteServices[0]
        XCTAssertEqual(service.name, "ValidService", "Should create the valid service")
        
        let actions = await service.getAvailableActions()
        XCTAssertEqual(actions.count, 1, "Valid service should have 1 action")
        XCTAssertTrue(actions.contains("valid"), "Valid service should have 'valid' action")
    }
    
    /// Test creating services with empty actions list
    @MainActor
    func testCreateFromCapabilitiesWithEmptyActions() async throws {
        // Arrange: Create service with no actions
        let serviceMetadata = ServiceMetadata(
            networkId: "test-network",
            servicePath: "empty-service",
            name: "EmptyService",
            version: "1.0.0",
            description: "Service with no actions",
            actions: [], // Empty actions
            registrationTime: UInt64(Date().timeIntervalSince1970),
            lastStartTime: nil
        )
        
        let config = CreateRemoteServicesConfig(
            services: [serviceMetadata],
            peerNodeId: "remote-peer-123",
            requestTimeoutMs: 5000
        )
        
        let dependencies = RemoteServiceDependencies(
            networkTransport: mockTransport,
            localNodeId: "local-node-456",
            logger: logger.child(component: .network),
            keystore: mockKeystore,
            labelResolverConfig: labelResolverConfig,
            labelResolverCache: labelResolverCache
        )
        
        // Act: Create RemoteServices from capabilities
        let remoteServices = try await RemoteService.createFromCapabilities(
            config: config,
            dependencies: dependencies
        )
        
        // Assert: Should create service with no actions
        XCTAssertEqual(remoteServices.count, 1, "Should create exactly 1 RemoteService instance")
        
        let service = remoteServices[0]
        XCTAssertEqual(service.name, "EmptyService", "Service name should match")
        
        let actions = await service.getAvailableActions()
        XCTAssertEqual(actions.count, 0, "Service should have no actions")
    }
}

// MARK: - Mock Classes

/// Mock implementation of CommonKeyManager for testing
private final class MockCommonKeyManager: CommonKeyManager {
    private let networkPublicKey = Data("mock-network-key".utf8)
    
    func getNetworkPublicKeyByNetworkId(networkId: String) async throws -> Data {
        return networkPublicKey
    }
    
    func encryptWithEnvelope(data: Data, networkPublicKey: Data?, profilePublicKeys: [Data]) async throws -> Data {
        // Simple mock implementation - just return the data as-is
        return data
    }
    
    func decryptEnvelope(envelopeData: Data) async throws -> Data {
        // Simple mock implementation - just return the data as-is
        return envelopeData
    }
    
    func ensureSymmetricKey(name: String) async throws -> Data {
        return Data("mock-symmetric-key-\(name)".utf8)
    }
    
    func encryptLocalData(data: Data) async throws -> Data {
        return data
    }
    
    func decryptLocalData(encryptedData: Data) async throws -> Data {
        return encryptedData
    }
    
    // MARK: - Additional CommonKeyManager methods
    
    func setPersistenceDirectory(_ path: String) async throws {
        // Mock implementation - do nothing
    }
    
    func enableAutoPersistence(_ enabled: Bool) async throws {
        // Mock implementation - do nothing
    }
    
    func wipePersistence() async throws {
        // Mock implementation - do nothing
    }
    
    func getKeystoreCapabilities() async throws -> KeystoreCapabilities {
        // Since the initializer is internal, we'll use a different approach
        // We'll create a mock that uses the same pattern as the real implementations
        // Let's try to create it using the same approach as the actual code
        let caps = RnDeviceKeystoreCaps(version: 1, flags: 0x0F)
        // Use the same approach as the real implementations
        return KeystoreCapabilities(version: caps.version, flags: caps.flags)
    }
    
    func flushState() async throws {
        // Mock implementation - do nothing
    }
    
    func registerAppleDeviceKeystore(label: String) async throws {
        // Mock implementation - do nothing
    }
    
    func encryptForNetwork(data: Data, networkPublicKey: Data) async throws -> Data {
        return data
    }
    
    func decryptNetworkData(encryptedEnvelope: Data) async throws -> Data {
        return encryptedEnvelope
    }
}

/// Mock implementation of NodeTransport for testing
private final class MockNodeTransport: NodeTransport {
    func start() async throws {
        // Mock implementation - do nothing
    }
    
    func stop() async throws {
        // Mock implementation - do nothing
    }
    
    func connectToPeer(peerInfo: SwiftFFI.PeerInfo) async throws {
        // Mock implementation - do nothing
    }
    
    func disconnectFromPeer(peerNodeId: String) async throws {
        // Mock implementation - do nothing
    }
    
    func sendRequest(path: String, payload: Data, correlationId: String) async throws {
        // Mock implementation - do nothing
    }
    
    func completeRequest(requestId: String, responsePayload: Data, profilePublicKey: Data?) async throws {
        // Mock implementation - do nothing
    }
    
    func publish(topic: String, payload: Data, options: PublishOptions) async throws {
        // Mock implementation - do nothing
    }
    
    func subscribe(topic: String, subscriptionId: String) async throws {
        // Mock implementation - do nothing
    }
    
    func unsubscribe(subscriptionId: String) async throws {
        // Mock implementation - do nothing
    }
    
    func localAddr() async throws -> String {
        return "mock://localhost:8080"
    }
    
    func updateLocalNodeInfo(nodeInfo: SwiftFFI.NodeInfo) async throws {
        // Mock implementation - do nothing
    }
    
    func request(path: String, correlationId: String, payload: Data, peerNodeId: String, networkPublicKey: Data?, profilePublicKeys: [Data]) async throws -> Data {
        // Simple mock implementation - return a mock response
        return Data("mock-response".utf8)
    }
}
