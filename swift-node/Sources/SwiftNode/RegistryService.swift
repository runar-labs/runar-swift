import Foundation
import SwiftCommon
import RunarSerializer

// MARK: - Registry Service

/// RegistryService handles internal service registry management
/// This service provides service discovery, metadata management, and state tracking
@MainActor
public final class RegistryService: ServiceBase {
    private let nodeId: String
    private var serviceRegistry: ServiceRegistry

    public init(logger: RunarLogger = RunarLogger(component: .registry), nodeId: String, serviceRegistry: ServiceRegistry) {
        self.nodeId = nodeId
        self.serviceRegistry = serviceRegistry
        super.init(name: "$registry", version: "1.0.0", path: "$registry", description: "Internal service registry management and discovery", logger: logger)
    }

    // MARK: - Service Lifecycle

    public override func performInit(_ context: LifecycleContext) async throws {
        self.networkId = context.networkId
    }

    public override func performStart(_ context: LifecycleContext) async throws {
        // Register all registry management actions
        try await registerServiceDiscoveryActions(context: context)
        try await registerServiceManagementActions(context: context)
        try await registerMetadataActions(context: context)
    }

    public override func performStop(_ context: LifecycleContext) async throws {
        // Cleanup resources
    }

    // MARK: - Service Discovery Actions

    private func registerServiceDiscoveryActions(context: LifecycleContext) async throws {
        // List all services
        try await context.registerAction("services/list") { [weak self] payload, ctx in
            guard let self = self else { throw BaseRunarError.serviceError("RegistryService not available", component: .registry) }

            let services = try await self.listServices()
            return AnyValue.struct(services)
        }

        // Get specific service info
        try await context.registerAction("services/{service_path}") { [weak self] payload, ctx in
            guard let self = self else { throw BaseRunarError.serviceError("RegistryService not available", component: .registry) }

            let servicePath = ctx.pathParams["service_path"] ?? "default"
            let serviceInfo = try await self.getServiceInfo(servicePath: servicePath)
            return AnyValue.struct(serviceInfo)
        }

        // Discover services by peer
        try await context.registerAction("services/discover") { [weak self] payload, ctx in
            guard let self = self else { throw BaseRunarError.serviceError("RegistryService not available", component: .registry) }

            guard let discoverRequest = payload?.deserialize(to: ServiceDiscoveryRequest.self) else {
                throw BaseRunarError.serializationError("Invalid discovery request", component: .registry)
            }

            let services = try await self.discoverServices(peerNodeId: discoverRequest.peerNodeId)
            return AnyValue.struct(services)
        }

        // Query service state
        try await context.registerAction("services/{service_path}/state") { [weak self] payload, ctx in
            guard let self = self else { throw BaseRunarError.serviceError("RegistryService not available", component: .registry) }

            let servicePath = ctx.pathParams["service_path"] ?? "default"
            let state = try await self.getServiceState(servicePath: servicePath)
            return AnyValue.struct(state)
        }
    }

    // MARK: - Service Management Actions

    private func registerServiceManagementActions(context: LifecycleContext) async throws {
        // Register a new service
        try await context.registerAction("services/register") { [weak self] payload, ctx in
            guard let self = self else { throw BaseRunarError.serviceError("RegistryService not available", component: .registry) }

            guard let registerRequest = payload?.deserialize(to: ServiceRegistrationRequest.self) else {
                throw BaseRunarError.serializationError("Invalid registration request", component: .registry)
            }

            try await self.registerService(request: registerRequest)
            return AnyValue.primitive(true)
        }

        // Unregister a service
        try await context.registerAction("services/unregister") { [weak self] payload, ctx in
            guard let self = self else { throw BaseRunarError.serviceError("RegistryService not available", component: .registry) }

            guard let unregisterRequest = payload?.deserialize(to: ServiceUnregistrationRequest.self) else {
                throw BaseRunarError.serializationError("Invalid unregistration request", component: .registry)
            }

            try await self.unregisterService(request: unregisterRequest)
            return AnyValue.primitive(true)
        }

        // Pause service
        try await context.registerAction("services/{service_path}/pause") { [weak self] payload, ctx in
            guard let self = self else { throw BaseRunarError.serviceError("RegistryService not available", component: .registry) }

            let servicePath = ctx.pathParams["service_path"] ?? "default"
            try await self.pauseService(servicePath: servicePath)
            return AnyValue.primitive(true)
        }

        // Resume service
        try await context.registerAction("services/{service_path}/resume") { [weak self] payload, ctx in
            guard let self = self else { throw BaseRunarError.serviceError("RegistryService not available", component: .registry) }

            let servicePath = ctx.pathParams["service_path"] ?? "default"
            try await self.resumeService(servicePath: servicePath)
            return AnyValue.primitive(true)
        }
    }

    // MARK: - Metadata Actions

    private func registerMetadataActions(context: LifecycleContext) async throws {
        // Get service metadata
        try await context.registerAction("metadata/{service_path}") { [weak self] payload, ctx in
            guard let self = self else { throw BaseRunarError.serviceError("RegistryService not available", component: .registry) }

            let servicePath = ctx.pathParams["service_path"] ?? "default"
            let metadata = try await self.getServiceMetadata(servicePath: servicePath)
            return AnyValue.struct(metadata)
        }

        // Update service metadata
        try await context.registerAction("metadata/{service_path}/update") { [weak self] payload, ctx in
            guard let self = self else { throw BaseRunarError.serviceError("RegistryService not available", component: .registry) }

            let servicePath = ctx.pathParams["service_path"] ?? "default"
            guard let updateRequest = payload?.deserialize(to: MetadataUpdateRequest.self) else {
                throw BaseRunarError.serializationError("Invalid metadata update request", component: .registry)
            }

            try await self.updateServiceMetadata(servicePath: servicePath, request: updateRequest)
            return AnyValue.primitive(true)
        }

        // Get node info
        try await context.registerAction("node/info") { [weak self] payload, ctx in
            guard let self = self else { throw BaseRunarError.serviceError("RegistryService not available", component: .registry) }

            let nodeInfo = try await self.getNodeInfo()
            return AnyValue.struct(nodeInfo)
        }

        // Get network topology
        try await context.registerAction("network/topology") { [weak self] payload, ctx in
            guard let self = self else { throw BaseRunarError.serviceError("RegistryService not available", component: .registry) }

            let topology = try await self.getNetworkTopology()
            return AnyValue.struct(topology)
        }
    }

    // MARK: - Service Discovery Implementation

    public func listServices() async throws -> ServiceListResponse {
        let services = serviceRegistry.getLocalServices()

        let serviceInfos = services.map { entry in
            ServiceInfo(
                servicePath: entry.servicePath.asString(),
                name: entry.name,
                version: entry.version,
                description: entry.description,
                state: entry.serviceState,
                registrationTime: entry.registrationTime,
                lastStartTime: entry.lastStartTime
            )
        }

        return ServiceListResponse(
            services: serviceInfos,
            totalCount: services.count,
            nodeId: nodeId
        )
    }

    public func getServiceInfo(servicePath: String) async throws -> ServiceInfoResponse {
        guard let service = serviceRegistry.getLocalService(servicePath: servicePath) else {
            throw BaseRunarError.serviceNotFound(servicePath: servicePath, component: .registry)
        }

        let info = ServiceInfo(
            servicePath: service.servicePath.asString(),
            name: service.name,
            version: service.version,
            description: service.description,
            state: service.serviceState,
            registrationTime: service.registrationTime,
            lastStartTime: service.lastStartTime
        )

        return ServiceInfoResponse(service: info)
    }

    public func discoverServices(peerNodeId: String) async throws -> ServiceDiscoveryResponse {
        // Get services for the specified peer
        var servicePaths: [String] = []
        let peerServices = serviceRegistry.getPeerServices(peerNodeId: peerNodeId)

        // Convert to service paths
        for servicePath in peerServices {
            servicePaths.append(servicePath)
        }

        return ServiceDiscoveryResponse(
            peerNodeId: peerNodeId,
            services: servicePaths,
            discoveredAt: Date()
        )
    }

    public func getServiceState(servicePath: String) async throws -> ServiceStateResponse {
        guard let service = serviceRegistry.getLocalService(servicePath: servicePath) else {
            throw BaseRunarError.serviceNotFound(servicePath: servicePath, component: .registry)
        }

        return ServiceStateResponse(
            servicePath: servicePath,
            state: service.serviceState,
            lastStartTime: service.lastStartTime,
            registrationTime: service.registrationTime
        )
    }

    // MARK: - Service Management Implementation

    public func registerService(request: ServiceRegistrationRequest) async throws {
        await serviceRegistry.registerLocalService(
            servicePath: request.servicePath,
            name: request.name,
            version: request.version,
            description: request.description
        )

        logger.info("Registered service: \(request.servicePath)")
    }

    public func unregisterService(request: ServiceUnregistrationRequest) async throws {
        // Note: ServiceRegistry doesn't have a direct unregister method
        // This would need to be implemented in ServiceRegistry
        logger.info("Unregistered service: \(request.servicePath)")
    }

    public func pauseService(servicePath: String) async throws {
        await serviceRegistry.updateLocalServiceState(servicePath: servicePath, newState: .paused)
        logger.info("Paused service: \(servicePath)")
    }

    public func resumeService(servicePath: String) async throws {
        await serviceRegistry.updateLocalServiceState(servicePath: servicePath, newState: .running)
        logger.info("Resumed service: \(servicePath)")
    }

    // MARK: - Metadata Implementation

    public func getServiceMetadata(servicePath: String) async throws -> ServiceMetadataResponse {
        guard let service = serviceRegistry.getLocalService(servicePath: servicePath) else {
            throw BaseRunarError.serviceNotFound(servicePath: servicePath, component: .registry)
        }

        let metadata = ServiceMetadata(
            networkId: service.servicePath.networkId,
            servicePath: service.servicePath.segments.joined(separator: "/"),
            name: service.name,
            version: service.version,
            description: service.description,
            actions: [], // Would need to be populated from action registry
            registrationTime: service.registrationTime,
            lastStartTime: service.lastStartTime
        )

        return ServiceMetadataResponse(metadata: metadata)
    }

    public func updateServiceMetadata(servicePath: String, request: MetadataUpdateRequest) async throws {
        // Note: This would need to be implemented in ServiceRegistry
        // For now, we'll just log the update
        logger.info("Updated metadata for service \(servicePath): \(request.updates)")
    }

    public func getNodeInfo() async throws -> NodeInfoResponse {
        let services = serviceRegistry.getLocalServices()

        return NodeInfoResponse(
            nodeId: nodeId,
            networkId: networkId ?? "default",
            serviceCount: services.count,
            uptime: ProcessInfo.processInfo.systemUptime,
            version: "1.0.0"
        )
    }

    public func getNetworkTopology() async throws -> NetworkTopologyResponse {
        let peers = serviceRegistry.getPeersWithSubscriptions()
        var peerServices: [String: [String]] = [:]

        for peerId in peers {
            let services = serviceRegistry.getPeerServices(peerNodeId: peerId)
            peerServices[peerId] = Array(services)
        }

        return NetworkTopologyResponse(
            nodeId: nodeId,
            peers: peerServices,
            totalPeers: peers.count,
            generatedAt: Date()
        )
    }
}

// MARK: - Request/Response Types

public struct ServiceDiscoveryRequest: Codable, Sendable {
    public let peerNodeId: String

    public init(peerNodeId: String) {
        self.peerNodeId = peerNodeId
    }
}

public struct ServiceRegistrationRequest: Codable, Sendable {
    public let servicePath: String
    public let name: String
    public let version: String
    public let description: String

    public init(servicePath: String, name: String, version: String, description: String) {
        self.servicePath = servicePath
        self.name = name
        self.version = version
        self.description = description
    }
}

public struct ServiceUnregistrationRequest: Codable, Sendable {
    public let servicePath: String

    public init(servicePath: String) {
        self.servicePath = servicePath
    }
}

public struct MetadataUpdateRequest: Codable, Sendable {
    public let updates: [String: String]

    public init(updates: [String: String]) {
        self.updates = updates
    }
}

public struct ServiceInfo: Codable, Sendable {
    public let servicePath: String
    public let name: String
    public let version: String
    public let description: String
    public let state: LocalServiceState
    public let registrationTime: Date
    public let lastStartTime: Date?

    public init(servicePath: String, name: String, version: String, description: String, state: LocalServiceState, registrationTime: Date, lastStartTime: Date?) {
        self.servicePath = servicePath
        self.name = name
        self.version = version
        self.description = description
        self.state = state
        self.registrationTime = registrationTime
        self.lastStartTime = lastStartTime
    }
}

public struct ServiceListResponse: Codable, Sendable {
    public let services: [ServiceInfo]
    public let totalCount: Int
    public let nodeId: String

    public init(services: [ServiceInfo], totalCount: Int, nodeId: String) {
        self.services = services
        self.totalCount = totalCount
        self.nodeId = nodeId
    }
}

public struct ServiceInfoResponse: Codable, Sendable {
    public let service: ServiceInfo

    public init(service: ServiceInfo) {
        self.service = service
    }
}

public struct ServiceDiscoveryResponse: Codable, Sendable {
    public let peerNodeId: String
    public let services: [String]
    public let discoveredAt: Date

    public init(peerNodeId: String, services: [String], discoveredAt: Date) {
        self.peerNodeId = peerNodeId
        self.services = services
        self.discoveredAt = discoveredAt
    }
}

public struct ServiceStateResponse: Codable, Sendable {
    public let servicePath: String
    public let state: LocalServiceState
    public let lastStartTime: Date?
    public let registrationTime: Date

    public init(servicePath: String, state: LocalServiceState, lastStartTime: Date?, registrationTime: Date) {
        self.servicePath = servicePath
        self.state = state
        self.lastStartTime = lastStartTime
        self.registrationTime = registrationTime
    }
}

public struct ServiceMetadataResponse: Codable, Sendable {
    public let metadata: ServiceMetadata

    public init(metadata: ServiceMetadata) {
        self.metadata = metadata
    }
}

public struct NodeInfoResponse: Codable, Sendable {
    public let nodeId: String
    public let networkId: String
    public let serviceCount: Int
    public let uptime: TimeInterval
    public let version: String

    public init(nodeId: String, networkId: String, serviceCount: Int, uptime: TimeInterval, version: String) {
        self.nodeId = nodeId
        self.networkId = networkId
        self.serviceCount = serviceCount
        self.uptime = uptime
        self.version = version
    }
}

public struct NetworkTopologyResponse: Codable, Sendable {
    public let nodeId: String
    public let peers: [String: [String]]
    public let totalPeers: Int
    public let generatedAt: Date

    public init(nodeId: String, peers: [String: [String]], totalPeers: Int, generatedAt: Date) {
        self.nodeId = nodeId
        self.peers = peers
        self.totalPeers = totalPeers
        self.generatedAt = generatedAt
    }
}

// MARK: - ServiceRegistry Extensions

extension ServiceRegistry {
    func getPeerServices(peerNodeId: String) -> Set<String> {
        return remoteServicesByPeer[peerNodeId] ?? []
    }

    func getPeersWithSubscriptions() -> [String] {
        return Array(remotePeerSubscriptions.keys)
    }
}
