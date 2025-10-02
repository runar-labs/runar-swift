import Foundation
import RunarSerializer
import SwiftCBOR
import SwiftCommon
import SwiftFFI

// MARK: - Missing Rust Schema Types

/// Action metadata structure matching Rust ActionMetadata
public struct ActionMetadata: Sendable, Codable {
    public let name: String
    public let description: String
    public let inputSchema: FieldSchema?
    public let outputSchema: FieldSchema?

    public init(name: String, description: String, inputSchema: FieldSchema? = nil, outputSchema: FieldSchema? = nil) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
    }
}

/// Service metadata structure matching Rust ServiceMetadata
public struct ServiceMetadata: Sendable, Codable {
    public let networkId: String
    public let servicePath: String
    public let name: String
    public let version: String
    public let description: String
    public let actions: [ActionMetadata]
    public let registrationTime: UInt64
    public let lastStartTime: UInt64?

    public init(
        networkId: String,
        servicePath: String,
        name: String,
        version: String,
        description: String,
        actions: [ActionMetadata] = [],
        registrationTime: UInt64,
        lastStartTime: UInt64? = nil
    ) {
        self.networkId = networkId
        self.servicePath = servicePath
        self.name = name
        self.version = version
        self.description = description
        self.actions = actions
        self.registrationTime = registrationTime
        self.lastStartTime = lastStartTime
    }
}

/// Schema data type enum matching Rust SchemaDataType
public enum SchemaDataType: Sendable, Codable {
    case string
    case int32
    case int64
    case float
    case double
    case boolean
    case timestamp
    case binary
    case object
    case array
    case reference(String)
    case union([SchemaDataType])
    case any
}

/// Field schema structure matching Rust FieldSchema
public indirect enum FieldSchema: Sendable, Codable {
    case primitive(
        name: String,
        dataType: SchemaDataType,
        description: String? = nil,
        nullable: Bool? = nil,
        defaultValue: String? = nil
    )
    case object(
        name: String,
        properties: [String: FieldSchema],
        description: String? = nil,
        nullable: Bool? = nil,
        defaultValue: String? = nil
    )
    case array(
        name: String,
        items: FieldSchema,
        description: String? = nil,
        nullable: Bool? = nil,
        defaultValue: String? = nil
    )

    public var name: String {
        switch self {
        case let .primitive(name, _, _, _, _),
             let .object(name, _, _, _, _),
             let .array(name, _, _, _, _):
            name
        }
    }

    public var dataType: SchemaDataType {
        switch self {
        case let .primitive(_, dataType, _, _, _):
            dataType
        case .object:
            .object
        case .array:
            .array
        }
    }
}

// MARK: - FFI Integration

/// Type alias for FFIKeys to use real NodeKeyManager from swift-ffi
public typealias FFIKeys = NodeKeyManager

// MARK: - Missing Types and Protocols

/// Protocol for network transport implementations
public protocol NodeTransport: AnyObject, Sendable {
    func start() async throws
    func stop() async throws
    func sendRequest(path: String, payload: Data, correlationId: String) async throws
    func completeRequest(requestId: String, responsePayload: Data, profilePublicKey: Data?) async throws
    func publish(topic: String, payload: Data, options: PublishOptions) async throws
    func subscribe(topic: String, subscriptionId: String) async throws
    func unsubscribe(subscriptionId: String) async throws
    func localAddr() async throws -> String
    func updateLocalNodeInfo(_ nodeInfo: Data) async throws
}

/// Protocol for load balancing strategies
public protocol LoadBalancingStrategy: Sendable {
    func selectHandler(handlers: [String]) async -> String?
}

/// Round-robin load balancer implementation (actor-based)
public actor RoundRobinLoadBalancer: LoadBalancingStrategy {
    private var currentIndex: Int = 0

    public init() {}

    public func selectHandler(handlers: [String]) async -> String? {
        guard !handlers.isEmpty else { return nil }
        let selected = handlers[currentIndex % handlers.count]
        currentIndex &+= 1
        return selected
    }
}

/// Protocol for node discovery
public protocol NodeDiscovery: Sendable {
    func start() async throws
    func stop() async throws
}

/// Discovery implementation using Swift FFI DiscoveryHandle
@MainActor
public final class Discovery: NodeDiscovery, Sendable {
    private let discoveryHandle: DiscoveryHandle
    private let logger: RunarLogger
    private var isStarted = false

    public init(discoveryHandle: DiscoveryHandle, logger: RunarLogger) {
        self.discoveryHandle = discoveryHandle
        self.logger = logger
        logger.trace("🔍 Discovery initialized")
    }

    public func start() async throws {
        guard !isStarted else {
            logger.trace("🔍 Discovery already started, skipping")
            return
        }

        logger.trace("🔍 Starting discovery...")
        try await discoveryHandle.startAnnouncing()
        isStarted = true
        logger.trace("🔍 Discovery started successfully")
    }

    public func stop() async throws {
        guard isStarted else {
            logger.trace("🔍 Discovery not started, skipping stop")
            return
        }

        logger.trace("🔍 Stopping discovery...")
        try await discoveryHandle.stopAnnouncing()
        isStarted = false
        logger.trace("🔍 Discovery stopped successfully")
    }

    /// Set discovery callbacks for handling discovered/updated/lost events
    public func setCallbacks(_ callbacks: DiscoveryCallbacks) async {
        logger.trace("🔍 Setting discovery callbacks")
        await discoveryHandle.setCallbacks(callbacks)
    }
    
    /// Update local peer info for discovery announcements
    public func updateLocalPeerInfo(peerInfoCbor: Data) async throws {
        logger.trace("🔍 Discovery: Updating local peer info")
        try await discoveryHandle.updateLocalPeerInfo(peerInfoCbor: peerInfoCbor)
        logger.trace("🔍 Discovery: Local peer info updated successfully")
    }
}

// MARK: - Real Transport Implementation

// TODO: Implement real transport using swift-ffi QuicTransport
// This should match the Rust transporter functionality

// MARK: - Real Discovery Implementation

// TODO: Implement real discovery using swift-ffi
// This should match the Rust discovery functionality

// MARK: - Resolver Cache (per-node)

/// Per-node resolver cache with TTL semantics, avoiding global shared state.
public actor ResolverCache {
    private struct CacheEntry: Sendable { let resolver: LabelResolver; let expiresAt: Date }
    private var storage: [String: CacheEntry] = [:]
    private let capacity: Int
    private let ttlSeconds: TimeInterval

    public init(capacity: Int = 1000, ttlSeconds: TimeInterval = 300) {
        self.capacity = capacity
        self.ttlSeconds = ttlSeconds
    }

    public func getOrCreateResolver(systemConfig: LabelResolverConfig, userProfilePublicKeys: [Data]) throws -> LabelResolver {
        let key = ResolverCache.makeKey(systemConfig: systemConfig, userProfilePublicKeys: userProfilePublicKeys)
        let now = Date()
        if let entry = storage[key], entry.expiresAt > now {
            return entry.resolver
        }

        // Evict expired entries
        storage = storage.filter { $0.value.expiresAt > now }
        // Enforce capacity (simple drop-oldest strategy)
        if storage.count >= capacity {
            let sorted = storage.sorted { $0.value.expiresAt < $1.value.expiresAt }
            if let oldestKey = sorted.first?.key {
                storage.removeValue(forKey: oldestKey)
            }
        }

        let resolver = try LabelResolver.createContextResolver(
            systemConfig: systemConfig,
            userProfilePublicKeys: userProfilePublicKeys
        )
        storage[key] = CacheEntry(resolver: resolver, expiresAt: now.addingTimeInterval(ttlSeconds))
        return resolver
    }

    private static func makeKey(systemConfig: LabelResolverConfig, userProfilePublicKeys: [Data]) -> String {
        var hasher = Hasher()
        for (label, value) in systemConfig.labelMappings.sorted(by: { $0.key < $1.key }) {
            hasher.combine(label)
            if let npk = value.networkPublicKey { hasher.combine(npk) }
            if let spec = value.userKeySpec { hasher.combine(String(describing: spec)) }
        }
        for key in userProfilePublicKeys {
            hasher.combine(key)
        }
        return String(hasher.finalize())
    }
}

/// Discovery provider configuration
public struct DiscoveryProviderConfig: Sendable, Codable {
    public let type: String
    public let config: [String: String]

    public init(type: String, config: [String: String] = [:]) {
        self.type = type
        self.config = config
    }
}

/// Discovery options

/// Registry Service - provides information about registered services
@MainActor
public final class RegistryService: AbstractService {
    public let name: String = "RegistryService"
    public let version: String = "1.0.0"
    public let path: String = "registry"
    public let description: String = "Internal registry service"

    public let logger: RunarLogger
    private let registryDelegate: RegistryDelegate

    public var networkId: String?

    public init(logger: RunarLogger, registryDelegate: RegistryDelegate) {
        self.logger = logger
        self.registryDelegate = registryDelegate
    }

    public func initService(_ context: LifecycleContext) async throws {
        logger.trace("RegistryService.initService: Starting action registration")

        // Register registry actions
        try await context.registerAction("services/list") { [weak self] payload, _ in
            guard let self else { return AnyValue.list([]) }

            // Get includeInternalServices parameter (default to false)
            logger.trace("RegistryService.services/list: payload = \(String(describing: payload))")
            let includeInternal: Bool
            if let payload {
                logger.trace("RegistryService.services/list: payload type = \(type(of: payload))")
                do {
                    let paramsDict = try await payload.asType() as [String: AnyValue]
                    logger.trace("RegistryService.services/list: paramsDict = \(paramsDict)")
                    if let includeInternalValue = paramsDict["includeInternal"] {
                        logger.trace("RegistryService.services/list: includeInternalValue = \(includeInternalValue)")
                        logger.trace("RegistryService.services/list: includeInternalValue type = \(type(of: includeInternalValue))")
                        includeInternal = try await includeInternalValue.asType() as Bool
                        logger.trace("RegistryService.services/list: includeInternal = \(includeInternal)")
                    } else {
                        logger.trace("RegistryService.services/list: includeInternal key not found")
                        includeInternal = false
                    }
                } catch {
                    logger.error("RegistryService.services/list: Failed to parse payload: \(error)")
                    logger.trace("RegistryService.services/list: includeInternal = false (default due to error)")
                    includeInternal = false
                }
            } else {
                logger.trace("RegistryService.services/list: No payload provided")
                includeInternal = false
            }

            // Get all service metadata
            let allMetadata = try await registryDelegate.getAllServiceMetadata(includeInternalServices: includeInternal)

            // Convert to AnyValue list (matching Rust implementation)
            let metadataList = Array(allMetadata.values).map { metadata in
                AnyValue.struct(metadata)
            }

            return AnyValue.list(metadataList)
        }

        try await context.registerAction("services/{service_path}") { [weak self] _, requestContext in
            guard let self else { return AnyValue.map([:]) }

            logger.trace("RegistryService.services/{service_path}: Called with context: \(String(describing: requestContext))")

            // Extract service_path parameter from path parameters
            guard let servicePathString = requestContext.pathParams["service_path"] else {
                logger.warning("RegistryService.services/{service_path}: Missing service_path parameter")
                throw ServiceRegistryError.invalidTopicPath("Missing service_path parameter")
            }

            logger.trace("RegistryService.services/{service_path}: Looking for service: \(servicePathString)")

            // Create TopicPath using networkId from requestContext
            let servicePath = try TopicPath(networkId: requestContext.networkId,
                                            segments: servicePathString.split(separator: "/").map(String.init))

            // Get service metadata
            if let metadata = await registryDelegate.getServiceMetadata(servicePath: servicePath) {
                // Service found, return metadata as struct (matching Rust behavior)
                logger.trace("RegistryService.services/{service_path}: Found service metadata: \(metadata.name)")
                let result = AnyValue.struct(metadata)
                logger.trace("RegistryService.services/{service_path}: Returning metadata result")
                return result
            } else {
                // Service not found, return null (matching Rust behavior)
                logger.trace("RegistryService.services/{service_path}: Service not found: \(servicePathString)")
                return AnyValue.null()
            }
        }

        try await context.registerAction("services/{service_path}/state") { [weak self] _, requestContext in
            guard let self else { return AnyValue.null() }

            logger.trace("RegistryService.services/{service_path}/state: Called with context: \(String(describing: requestContext))")

            // Extract service_path parameter from path parameters
            guard let servicePathString = requestContext.pathParams["service_path"] else {
                logger.warning("RegistryService.services/{service_path}/state: Missing service_path parameter")
                throw ServiceRegistryError.invalidTopicPath("Missing service_path parameter")
            }

            logger.trace("RegistryService.services/{service_path}/state: Looking for service state: \(servicePathString)")

            // Create TopicPath using networkId from requestContext
            let servicePath = try TopicPath(networkId: requestContext.networkId,
                                            segments: servicePathString.split(separator: "/").map(String.init))

            // Get service state
            guard let state = await registryDelegate.getLocalServiceState(servicePath: servicePath) else {
                logger.warning("RegistryService.services/{service_path}/state: Service not found: \(servicePathString)")
                return AnyValue.null()
            }

            // Return ServiceState directly as primitive (matching Rust behavior)
            let result = AnyValue.primitive(state.rawValue)
            logger.trace("RegistryService.services/{service_path}/state: state.rawValue = \(state.rawValue)")
            logger.trace("RegistryService.services/{service_path}/state: servicePathString = \(servicePathString)")
            logger.trace("RegistryService.services/{service_path}/state: Returning result: \(result)")
            return result
        }

        // Register pause service action
        try await context.registerAction("services/{service_path}/pause") { [weak self] _, requestContext in
            guard let self else { return AnyValue.null() }

            logger.trace("RegistryService.services/{service_path}/pause: Called with context: \(String(describing: requestContext))")

            // Extract service_path parameter from path parameters
            guard let servicePathString = requestContext.pathParams["service_path"] else {
                logger.warning("RegistryService.services/{service_path}/pause: Missing service_path parameter")
                throw ServiceRegistryError.invalidTopicPath("Missing service_path parameter")
            }

            logger.trace("RegistryService.services/{service_path}/pause: Looking for service to pause: \(servicePathString)")

            // Create TopicPath using networkId from requestContext
            let servicePath = try TopicPath(networkId: requestContext.networkId,
                                            segments: servicePathString.split(separator: "/").map(String.init))

            // Get current state first to check if service exists
            if let currentState = await registryDelegate.getLocalServiceState(servicePath: servicePath) {
                // Validate that the service can be paused
                try await registryDelegate.validatePauseTransition(servicePath: servicePath)
                try await registryDelegate.updateLocalServiceStateIfValid(
                    servicePath: servicePath,
                    newState: .paused,
                    currentState: currentState
                )

                logger.trace("RegistryService.services/{service_path}/pause: Service '\(servicePathString)' paused successfully")
                return AnyValue.primitive(ServiceState.paused.rawValue)
            } else {
                logger.trace("RegistryService.services/{service_path}/pause: Service '\(servicePathString)' not found")
                return AnyValue.null()
            }
        }

        // Register resume service action
        try await context.registerAction("services/{service_path}/resume") { [weak self] _, requestContext in
            guard let self else { return AnyValue.null() }

            logger.trace("RegistryService.services/{service_path}/resume: Called with context: \(String(describing: requestContext))")

            // Extract service_path parameter from path parameters
            guard let servicePathString = requestContext.pathParams["service_path"] else {
                logger.warning("RegistryService.services/{service_path}/resume: Missing service_path parameter")
                throw ServiceRegistryError.invalidTopicPath("Missing service_path parameter")
            }

            logger.trace("RegistryService.services/{service_path}/resume: Looking for service to resume: \(servicePathString)")

            // Create TopicPath using networkId from requestContext
            let servicePath = try TopicPath(networkId: requestContext.networkId,
                                            segments: servicePathString.split(separator: "/").map(String.init))

            // Get current state first to check if service exists
            if let currentState = await registryDelegate.getLocalServiceState(servicePath: servicePath) {
                // Validate that the service can be resumed
                try await registryDelegate.validateResumeTransition(servicePath: servicePath)
                try await registryDelegate.updateLocalServiceStateIfValid(
                    servicePath: servicePath,
                    newState: .running,
                    currentState: currentState
                )

                logger.trace("RegistryService.services/{service_path}/resume: Service '\(servicePathString)' resumed successfully")
                return AnyValue.primitive(ServiceState.running.rawValue)
            } else {
                logger.trace("RegistryService.services/{service_path}/resume: Service '\(servicePathString)' not found")
                return AnyValue.null()
            }
        }

        logger.trace("RegistryService.initService: Action registration completed")
    }

    public func start(_: LifecycleContext) async throws {
        logger.trace("Registry service started")
    }

    public func stop(_: LifecycleContext) async throws {
        logger.trace("Registry service stopped")
    }

    public func setNetworkId(_ networkId: String) {
        self.networkId = networkId
    }
}

/// Keys Service - provides key management functionality
@MainActor
public final class KeysService: AbstractService {
    public let name: String = "KeysService"
    public let version: String = "1.0.0"
    public let path: String = "keys"
    public let description: String = "Internal keys service"

    public let logger: RunarLogger
    private let nodeDelegate: NodeDelegate

    public var networkId: String?

    public init(logger: RunarLogger, nodeDelegate: NodeDelegate) {
        self.logger = logger
        self.nodeDelegate = nodeDelegate
    }

    public func initService(_ context: LifecycleContext) async throws {
        // Register keys actions
        try await context.registerAction("ensure_symmetric_key") { _, _ in
            // Ensure symmetric key exists
            AnyValue.map([:])
        }

        try await context.registerAction("get_public_key") { _, _ in
            // Get public key
            AnyValue.map([:])
        }
    }

    public func start(_: LifecycleContext) async throws {
        logger.trace("Keys service started")
    }

    public func stop(_: LifecycleContext) async throws {
        logger.trace("Keys service stopped")
    }

    public func setNetworkId(_ networkId: String) {
        self.networkId = networkId
    }
}

// MARK: - Context Structs

/// Lifecycle context for service initialization, start, and stop operations
public struct LifecycleContext: Sendable {
    /// Network ID for the context
    public let networkId: String
    /// Service path - identifies the service within the network
    public let servicePath: String
    /// Optional configuration data
    public let config: AnyValue?
    /// Logger instance with service context
    public let logger: RunarLogger
    /// Node delegate for node operations
    public let nodeDelegate: NodeDelegate

    public init(
        networkId: String,
        servicePath: String,
        config: AnyValue? = nil,
        logger: RunarLogger,
        nodeDelegate: NodeDelegate
    ) {
        self.networkId = networkId
        self.servicePath = servicePath
        self.config = config
        self.logger = logger
        self.nodeDelegate = nodeDelegate
    }

    /// Create a new LifecycleContext with a topic path and logger
    public init(topicPath: TopicPath, nodeDelegate: NodeDelegate, logger: RunarLogger) {
        networkId = topicPath.networkId
        servicePath = topicPath.servicePath
        config = nil
        self.logger = logger
        self.nodeDelegate = nodeDelegate
    }

    /// Register an action handler for this service
    public func registerAction(_ action: String, handler: @escaping ActionHandler) async throws {
        try await nodeDelegate.registerAction(
            networkId: networkId,
            servicePath: servicePath,
            action: action,
            handler: handler
        )
    }
}

/// Request context for handling action requests
public struct RequestContext: Sendable {
    /// Complete topic path for this request
    public let topicPath: TopicPath
    /// Network ID for this request
    public let networkId: String
    /// Metadata for this request
    public let metadata: [String: AnyValue]
    /// Logger for this context
    public let logger: RunarLogger
    /// Path parameters extracted from template matching
    public let pathParams: [String: String]
    /// Node delegate for making requests or publishing events
    public let nodeDelegate: NodeDelegate

    public init(
        topicPath: TopicPath,
        networkId: String,
        metadata: [String: AnyValue] = [:],
        logger: RunarLogger,
        pathParams: [String: String] = [:],
        nodeDelegate: NodeDelegate
    ) {
        self.topicPath = topicPath
        self.networkId = networkId
        self.metadata = metadata
        self.logger = logger
        self.pathParams = pathParams
        self.nodeDelegate = nodeDelegate
    }
}

/// Event context for handling event publishing and subscription
public struct EventContext: Sendable {
    /// Complete topic path for this event
    public let topicPath: TopicPath
    /// Logger instance specific to this context
    public let logger: RunarLogger
    /// Node delegate for making requests or publishing events
    public let nodeDelegate: NodeDelegate
    /// Delivery options used when publishing this event
    public let deliveryOptions: PublishOptions?
    /// Whether this event is local or remote
    public let isLocal: Bool

    public init(
        topicPath: TopicPath,
        logger: RunarLogger,
        nodeDelegate: NodeDelegate,
        deliveryOptions: PublishOptions? = nil,
        isLocal: Bool = true
    ) {
        self.topicPath = topicPath
        self.logger = logger
        self.nodeDelegate = nodeDelegate
        self.deliveryOptions = deliveryOptions
        self.isLocal = isLocal
    }
}

/// Protocol for node delegate
public protocol NodeDelegate: AnyObject, Sendable {
    func registerAction(networkId: String, servicePath: String, action: String, handler: @escaping ActionHandler) async throws
    func unregisterAction(networkId: String, servicePath: String, action: String) async throws
    func subscribeToEvents(networkId: String, servicePath: String, handler: @escaping EventHandler) async throws -> String
    func unsubscribeFromEvents(subscriptionId: String) async throws
    func subscribe(topic: String, options: EventRegistrationOptions?, callback: @escaping EventHandler) async throws -> String
    func publish(topic: String, data: AnyValue?) async throws
}

/// Keys Delegate trait for keys service operations
///
/// INTENTION: Provide a dedicated interface for the Keys Service
/// to interact with the Node without creating circular references.
public protocol KeysDelegate: AnyObject {
    func ensureSymmetricKey(keyName: String) async throws -> AnyValue
}

/// Registry Delegate trait for registry service operations
///
/// INTENTION: Provide a dedicated interface for the Registry Service
/// to interact with the Node without creating circular references.
public protocol RegistryDelegate: AnyObject, Sendable {
    func getLocalServiceState(servicePath: TopicPath) async -> ServiceState?
    func getRemoteServiceState(servicePath: TopicPath) async -> ServiceState?
    func getServiceMetadata(servicePath: TopicPath) async -> ServiceMetadata?
    func getAllServiceMetadata(includeInternalServices: Bool) async throws -> [String: ServiceMetadata]
    func getActionsMetadata(serviceTopicPath: TopicPath) async -> [ActionMetadata]
    func registerRemoteActionHandler(topicPath: TopicPath, handler: ActionHandler) async throws
    func removeRemoteActionHandler(topicPath: TopicPath) async throws
    func registerRemoteEventHandler(topicPath: TopicPath, handler: EventHandler) async throws
    func removeRemoteEventHandler(topicPath: TopicPath) async throws

    /// Update service state only if the transition is valid
    func updateLocalServiceStateIfValid(servicePath: TopicPath, newState: ServiceState, currentState: ServiceState) async throws

    /// Validate that a service can be paused
    func validatePauseTransition(servicePath: TopicPath) async throws

    /// Validate that a service can be resumed
    func validateResumeTransition(servicePath: TopicPath) async throws
}

/// Action handler type
public typealias ActionHandler = @Sendable (AnyValue?, RequestContext) async throws -> AnyValue

/// Event handler type
public typealias EventHandler = @Sendable (AnyValue?) async -> Void

/// Publish options
public struct PublishOptions: Sendable {
    public var broadcast: Bool
    public var guaranteedDelivery: Bool
    public var retainFor: TimeInterval?
    public var target: String?

    public init(
        broadcast: Bool = false,
        guaranteedDelivery: Bool = false,
        retainFor: TimeInterval? = nil,
        target: String? = nil
    ) {
        self.broadcast = broadcast
        self.guaranteedDelivery = guaranteedDelivery
        self.retainFor = retainFor
        self.target = target
    }
}

/// On options
public struct OnOptions: Sendable {
    public var timeout: TimeInterval
    public var includePast: TimeInterval?

    public init(timeout: TimeInterval = 5.0, includePast: TimeInterval? = nil) {
        self.timeout = timeout
        self.includePast = includePast
    }
}

// MARK: - Logging Configuration

/// Log levels matching standard logging levels
public enum LogLevel: String, CaseIterable, Sendable, Codable {
    case error
    case warn
    case info
    case debug
    case trace
    case off
}

/// Logging configuration for the node and its services
public struct LoggerConfig: Sendable, Codable {
    /// Default log level for all runar modules
    public let defaultLevel: LogLevel

    public init(defaultLevel: LogLevel = .info) {
        self.defaultLevel = defaultLevel
    }

    /// Create a default info-level logging configuration
    public static func defaultInfo() -> LoggerConfig {
        LoggerConfig(defaultLevel: .info)
    }
}

// MARK: - Network Configuration

/// Network configuration for peer-to-peer communication
public struct NetworkConfig: Sendable, Codable {
    /// Transport type (QUIC, etc.)
    public let transportType: String
    /// Base transport options
    public let bindAddress: String?
    /// Connection timeout in milliseconds
    public let connectionTimeoutMs: UInt32
    /// Request timeout in milliseconds
    public let requestTimeoutMs: UInt32
    /// Maximum number of connections
    public let maxConnections: UInt32
    /// Maximum message size in bytes
    public let maxMessageSize: UInt32
    /// Maximum chunk size in bytes
    public let maxChunkSize: UInt32
    /// Discovery options
    public let discoveryOptions: SwiftFFI.DiscoveryOptions?
    /// Discovery providers
    public let discoveryProviders: [DiscoveryProviderConfig]

    public init(
        transportType: String = "quic",
        bindAddress: String? = nil,
        connectionTimeoutMs: UInt32 = 30000,
        requestTimeoutMs: UInt32 = 30000,
        maxConnections: UInt32 = 100,
        maxMessageSize: UInt32 = 1024 * 1024, // 1MB
        maxChunkSize: UInt32 = 64 * 1024, // 64KB
        discoveryOptions: SwiftFFI.DiscoveryOptions? = nil,
        discoveryProviders: [DiscoveryProviderConfig] = []
    ) {
        self.transportType = transportType
        self.bindAddress = bindAddress
        self.connectionTimeoutMs = connectionTimeoutMs
        self.requestTimeoutMs = requestTimeoutMs
        self.maxConnections = maxConnections
        self.maxMessageSize = maxMessageSize
        self.maxChunkSize = maxChunkSize
        self.discoveryOptions = discoveryOptions
        self.discoveryProviders = discoveryProviders
    }
}

// MARK: - Node Configuration

/// Configuration for a Runar Node instance.
///
/// This struct provides all the configuration options needed to create and configure
/// a Node. It uses the builder pattern for easy configuration.
///
/// # Examples
///
/// ```swift
/// // Basic configuration
/// let config = NodeConfig(defaultNetworkId: "my-network")
///
/// // Advanced configuration with networking
/// let config = NodeConfig(defaultNetworkId: "my-network")
///     .withNetworkConfig(NetworkConfig())
///     .withRequestTimeout(5000)
///     .withAdditionalNetworks(["backup-network"])
/// ```
///
/// # Default Values
///
/// - `requestTimeoutMs`: 30000 (30 seconds)
/// - `LoggerConfig`: Info level logging
/// - `networkConfig`: None (networking disabled)
/// - `networkIds`: Empty (only default network)
///
/// # Security Note
///
/// The `keyManager` must be provided via `withKeyManager()` for production use.
/// This contains the node's cryptographic credentials and should be stored securely.
public struct NodeConfig: Sendable {
    /// Primary network identifier this node belongs to.
    ///
    /// All services registered without a specific network ID will use this as their default.
    /// This is the main network for peer discovery and service communication.
    public let defaultNetworkId: String

    /// Additional network IDs this node participates in.
    ///
    /// Allows the node to be part of multiple networks simultaneously.
    /// Services can be registered to specific networks or use the default.
    public var networkIds: [String]

    /// Network configuration for peer-to-peer communication.
    ///
    /// If `nil`, networking features are disabled and the node operates in local-only mode.
    /// When provided, enables peer discovery, remote service calls, and distributed features.
    public var networkConfig: NetworkConfig?

    /// Logging configuration for the node and its services.
    ///
    /// Controls log levels, output format, and logging destinations.
    /// If `nil`, default Info-level logging is applied.
    public var LoggerConfig: LoggerConfig?

    /// Request timeout in milliseconds for all service requests.
    ///
    /// This timeout applies to both local and remote service calls.
    /// Default is 30 seconds (30000ms).
    public var requestTimeoutMs: UInt64

    /// REQUIRED: Label resolver configuration for system labels
    /// These are static mappings known at node startup
    /// NO OPTION - This field is REQUIRED for all nodes
    public var labelResolverConfig: LabelResolverConfig

    /// Key manager containing node credentials.
    ///
    /// This field is private and must be set via `withKeyManager()`.
    /// Contains the node's cryptographic keys and certificates.
    private var keyManager: FFIKeys?

    /// Get the key manager for this configuration
    func getKeyManager() throws -> FFIKeys {
        guard let keyManager else {
            throw NodeError.missingKeyManager("Key manager not set in configuration")
        }
        return keyManager
    }

    /// Create a new Node configuration with the specified network ID.
    ///
    /// This constructor creates a basic configuration suitable for development and testing.
    /// For production use, you must call `withKeyManager()` to provide the node's
    /// cryptographic credentials.
    ///
    /// # Arguments
    ///
    /// * `defaultNetworkId` - Primary network this node belongs to
    ///
    /// # Examples
    ///
    /// ```swift
    /// // Basic configuration
    /// let config = NodeConfig(defaultNetworkId: "my-network")
    ///
    /// // Production configuration requires key manager
    /// let config = NodeConfig(defaultNetworkId: "my-network")
    ///     .withKeyManager(keysManager)
    /// ```
    public init(defaultNetworkId: String) {
        // Create default label resolver config with system label
        let labelResolverConfig = LabelResolverConfig(
            labelMappings: [
                "system": LabelValue(
                    networkPublicKey: nil, // Will be resolved at runtime
                    userKeySpec: nil
                ),
            ]
        )

        self.defaultNetworkId = defaultNetworkId
        networkIds = []
        networkConfig = nil
        LoggerConfig = SwiftNode.LoggerConfig.defaultInfo() // Default to Info logging
        keyManager = nil // Must be set via withKeyManager()
        requestTimeoutMs = 30000 // 30 seconds
        self.labelResolverConfig = labelResolverConfig
    }

    /// Set the label resolver configuration for system labels.
    ///
    /// # Arguments
    ///
    /// * `config` - Label resolver configuration with system label mappings
    ///
    /// # Examples
    ///
    /// ```swift
    /// let config = NodeConfig(defaultNetworkId: "my-network")
    ///     .withLabelResolverConfig(LabelResolverConfig(
    ///         labelMappings: [
    ///             "system": LabelValue(
    ///                 networkPublicKey: Data([1, 2, 3, 4]), // Example network key
    ///                 userKeySpec: nil
    ///             ),
    ///             "current_user": LabelValue(
    ///                 networkPublicKey: Data([5, 6, 7, 8]), // Example network key
    ///                 userKeySpec: .currentUser
    ///             )
    ///         ]
    ///     ))
    /// ```
    public func withLabelResolverConfig(_ config: LabelResolverConfig) -> NodeConfig {
        var newConfig = self
        newConfig.labelResolverConfig = config
        return newConfig
    }

    /// Add network configuration to enable peer-to-peer communication.
    ///
    /// # Arguments
    ///
    /// * `config` - Network configuration including transport settings and discovery options
    ///
    /// # Examples
    ///
    /// ```swift
    /// let config = NodeConfig(defaultNetworkId: "my-network")
    ///     .withNetworkConfig(NetworkConfig())
    /// ```
    public func withNetworkConfig(_ config: NetworkConfig) -> NodeConfig {
        var newConfig = self
        newConfig.networkConfig = config
        return newConfig
    }

    /// Configure logging behavior for the node and its services.
    ///
    /// # Arguments
    ///
    /// * `config` - Logging configuration specifying levels, format, and destinations
    ///
    /// # Examples
    ///
    /// ```swift
    /// let config = NodeConfig(defaultNetworkId: "my-network")
    ///     .withLoggerConfig(LoggerConfig.defaultInfo())
    /// ```
    public func withLoggerConfig(_ config: LoggerConfig) -> NodeConfig {
        var newConfig = self
        newConfig.LoggerConfig = config
        return newConfig
    }

    /// Add additional network IDs for multi-network participation.
    ///
    /// This allows the node to participate in multiple networks simultaneously.
    /// Services can be registered to specific networks or use the default network.
    ///
    /// # Arguments
    ///
    /// * `networkIds` - Array of additional network identifiers
    ///
    /// # Examples
    ///
    /// ```swift
    /// let config = NodeConfig(defaultNetworkId: "my-network")
    ///     .withAdditionalNetworks(["backup", "testing"])
    /// ```
    public func withAdditionalNetworks(_ networkIds: [String]) -> NodeConfig {
        var newConfig = self
        newConfig.networkIds = networkIds
        return newConfig
    }

    /// Set the request timeout for all service requests.
    ///
    /// This timeout applies to both local and remote service calls.
    /// The default is 30 seconds (30000ms).
    ///
    /// # Arguments
    ///
    /// * `timeoutMs` - Timeout in milliseconds
    ///
    /// # Examples
    ///
    /// ```swift
    /// let config = NodeConfig(defaultNetworkId: "my-network")
    ///     .withRequestTimeout(5000) // 5 second timeout
    /// ```
    public func withRequestTimeout(_ timeoutMs: UInt64) -> NodeConfig {
        var newConfig = self
        newConfig.requestTimeoutMs = timeoutMs
        return newConfig
    }

    /// Set the key manager for production use.
    ///
    /// This method is required for production deployments. The key manager
    /// contains the node's cryptographic credentials and must be provided securely.
    ///
    /// # Arguments
    ///
    /// * `keyManager` - Key manager containing node credentials
    ///
    /// # Security Note
    ///
    /// The key manager contains sensitive cryptographic material and should
    /// be stored securely and transmitted over secure channels.
    ///
    /// # Examples
    ///
    /// ```swift
    /// let config = NodeConfig(defaultNetworkId: "my-network")
    ///     .withKeyManager(keysManager)
    /// ```
    public func withKeyManager(_ keyManager: FFIKeys) -> NodeConfig {
        var newConfig = self
        newConfig.keyManager = keyManager
        return newConfig
    }

    /// Get the key manager if available
    func getKeyManager() -> FFIKeys? {
        keyManager
    }
}

// MARK: - Display Implementation

extension NodeConfig: CustomStringConvertible {
    public var description: String {
        var result = "NodeConfig: default_network:\(defaultNetworkId) request_timeout:\(requestTimeoutMs)ms"

        // Add network configuration details if available
        if let networkConfig {
            result += " network:\(networkConfig.transportType) bind_address:\(networkConfig.bindAddress ?? "auto")"
        }

        return result
    }
}

// MARK: - Node Information

/// Node information structure containing metadata about a node
public struct NodeInfo: Sendable, Codable {
    /// Node's public key
    public let nodePublicKey: Data
    /// Network IDs this node participates in
    public let networkIds: [String]
    /// Network addresses for this node
    public let addresses: [String]
    /// Node metadata including services and subscriptions
    public let nodeMetadata: NodeMetadata
    /// Version number for this node info
    public let version: Int64

    public init(
        nodePublicKey: Data,
        networkIds: [String],
        addresses: [String],
        nodeMetadata: NodeMetadata,
        version: Int64 = 0
    ) {
        self.nodePublicKey = nodePublicKey
        self.networkIds = networkIds
        self.addresses = addresses
        self.nodeMetadata = nodeMetadata
        self.version = version
    }
}

/// Node metadata containing services and subscriptions
public struct NodeMetadata: Sendable, Codable {
    /// List of services provided by this node
    public let services: [String]
    /// List of event subscriptions for this node
    public let subscriptions: [String]

    public init(services: [String] = [], subscriptions: [String] = []) {
        self.services = services
        self.subscriptions = subscriptions
    }
}

// MARK: - Service Task

/// Service task for tracking service lifecycle
public struct ServiceTask: Sendable, Codable {
    /// Service path
    public let servicePath: String
    /// Task identifier
    public let taskId: String
    /// Task status
    public let status: String

    public init(servicePath: String, taskId: String, status: String) {
        self.servicePath = servicePath
        self.taskId = taskId
        self.status = status
    }
}

// MARK: - Retained Events

/// Retained event entry with timestamp and data
public struct RetainedEventEntry: Sendable {
    /// Timestamp when event was published
    public let timestamp: Date
    /// Event data (optional)
    public let data: AnyValue?

    public init(timestamp: Date, data: AnyValue?) {
        self.timestamp = timestamp
        self.data = data
    }
}

/// Actor-based retained deque for storing events with TTL and capacity management
/// Matches Rust: type RetainedDeque = VecDeque<(Instant, Option<ArcValue>)>
public actor RetainedDeque {
    /// Maximum number of retained events per topic (matches Rust MAX_RETAIN_PER_TOPIC = 16)
    public static let maxRetainPerTopic: Int = 16

    /// Storage for retained events
    private var entries: [RetainedEventEntry] = []

    /// Capacity limit for this deque
    private let capacity: Int

    /// TTL in seconds for event retention
    private let ttlSeconds: TimeInterval

    public init(capacity: Int = 16, ttlSeconds: TimeInterval = 300) {
        self.capacity = capacity
        self.ttlSeconds = ttlSeconds
    }

    /// Append a new event entry to the deque
    /// - Parameters:
    ///   - entry: The event entry to append
    public func append(_ entry: RetainedEventEntry) {
        // Prune expired entries first
        pruneExpired(now: entry.timestamp)

        // Enforce capacity by dropping oldest entries
        while entries.count >= capacity {
            entries.removeFirst()
        }

        // Add the new entry
        entries.append(entry)
    }

    /// Append a new event with current timestamp
    /// - Parameters:
    ///   - timestamp: Timestamp for the event (defaults to current time)
    ///   - data: Event data (optional)
    public func append(timestamp: Date = Date(), data: AnyValue?) {
        let entry = RetainedEventEntry(timestamp: timestamp, data: data)
        append(entry)
    }

    /// Prune expired entries based on TTL
    /// - Parameter now: Current time for TTL calculation
    public func pruneExpired(now: Date = Date()) {
        let cutoffTime = now.addingTimeInterval(-ttlSeconds)
        entries.removeAll { $0.timestamp < cutoffTime }
    }

    /// Get the latest events up to the specified limit
    /// - Parameter limit: Maximum number of events to return
    /// - Returns: Array of latest events (most recent first)
    public func getLatest(limit: Int) -> [RetainedEventEntry] {
        pruneExpired()
        let count = min(limit, entries.count)
        return Array(entries.suffix(count).reversed())
    }

    /// Get all events in the deque (for snapshot)
    /// - Returns: Array of all events (oldest first)
    public func snapshot() -> [RetainedEventEntry] {
        pruneExpired()
        return entries
    }

    /// Get the count of retained events
    public var count: Int {
        entries.count
    }

    /// Check if the deque is empty
    public var isEmpty: Bool {
        entries.isEmpty
    }
}

// MARK: - Node

/// Main Node implementation matching Rust structure
@MainActor
public final class Node {
    // MARK: - Core Properties

    /// Debounce state for notify_node_change
    private var debounceTask: Task<Void, Never>?

    /// Default network id to be used when services are added without a network ID
    public let networkId: String

    /// Network IDs that this node participates in
    public let networkIds: [String]

    /// The node ID for this node
    public let nodeId: String

    /// Node's public key
    public let nodePublicKey: Data

    /// Configuration for this node
    public let config: NodeConfig

    /// The service registry for this node
    public let serviceRegistry: ServiceRegistry

    /// Centralized peer directory (single source of truth)
    /// Matches Rust: Arc<DashMap<String, NodeInfo>>
    private let remoteNodeInfo: ShardedConcurrentMap<String, NodeInfo>

    /// Debounce repeated discovery events per peer
    /// Matches Rust: Arc<DashMap<String, Instant>>
    private let discoverySeenTimes: ShardedConcurrentMap<String, Date>

    /// Logger instance
    public let logger: RunarLogger

    /// Flag indicating if the node is running
    private var running: Bool = false

    /// Flag indicating if this node supports networking
    /// This is set when networking is enabled in the config
    public let supportsNetworking: Bool

    /// Network transport for connecting to remote nodes
    private var networkTransport: (any NodeTransport)?

    /// Network discovery providers
    private var networkDiscoveryProviders: [NodeDiscovery]?

    /// Load balancer for selecting remote handlers
    private var loadBalancer: RoundRobinLoadBalancer

    /// System label configuration for dynamic resolver creation
    public let systemLabelConfig: LabelResolverConfig

    /// Per-node label resolver cache for better concurrency and isolation
    public let labelResolverCache: ResolverCache

    /// Registry version for tracking changes
    private var registryVersion: Int64 = 0

    /// Key manager containing node credentials
    public let keysManager: FFIKeys

    /// Service tasks for tracking service lifecycle
    private var serviceTasks: [ServiceTask] = []

    /// Local node information
    public let localNodeInfo: NodeInfo

    /// Retained event store: exact full topic -> deque of (timestamp, data)
    /// Matches Rust: Arc<RetainedEventsMap> where RetainedEventsMap = DashMap<String, RetainedDeque>
    private let retainedEvents: ShardedConcurrentMap<String, RetainedDeque>

    /// Index of exact topics for wildcard lookups
    /// Matches Rust: Arc<RwLock<PathTrie<String>>>
    private var retainedIndex: PathTrie<String> = PathTrie()

    // MARK: - Computed Properties

    /// Check if the node is currently running
    public var isRunning: Bool { running }

    /// Get the current registry version
    public var currentRegistryVersion: Int64 { registryVersion }

    /// Get the current service tasks
    public var currentServiceTasks: [ServiceTask] { serviceTasks }

    // MARK: - Initialization

    /// Create a new Node with the given configuration.
    ///
    /// This constructor initializes a new Node instance with the specified configuration,
    /// setting up all necessary components and internal state. This is the primary
    /// entry point for creating a Node instance.
    ///
    /// # Arguments
    ///
    /// * `config` - Node configuration including network settings and credentials
    ///
    /// # Returns
    ///
    /// Returns a new Node instance ready for service registration and startup.
    ///
    /// # Important Notes
    ///
    /// - **Services are not started**: Call `start()` separately after registering services
    /// - **Key manager state required**: Production configurations must include cryptographic credentials
    /// - **Networking disabled by default**: Enable networking via `NetworkConfig` in the configuration
    ///
    /// # Examples
    ///
    /// ```swift
    /// let config = NodeConfig(defaultNetworkId: "my-network")
    ///     .withKeyManager(keysManager)
    /// let node = try await Node.new(config: config)
    /// ```
    ///
    /// # Errors
    ///
    /// This method will return an error if:
    /// - The configuration is invalid
    /// - Key manager state cannot be deserialized
    /// - Internal components fail to initialize
    public static func new(config: NodeConfig) async throws -> Node {
        // Apply logging configuration (default to Info level if none provided)
        if config.LoggerConfig != nil {
            // Apply logging configuration here
            // This would integrate with the logging system
        } else {
            // Apply default Info logging when no configuration is provided
            _ = LoggerConfig.defaultInfo()
            // Apply default logging configuration
        }

        // Clone fields before moving config
        let defaultNetworkId = config.defaultNetworkId
        let networkingEnabled = config.networkConfig != nil

        var networkIds = config.networkIds
        networkIds.append(defaultNetworkId)
        networkIds = Array(Set(networkIds)) // Remove duplicates

        // Convert SwiftNode.LoggerConfig to SwiftCommon.LoggerConfig
        let commonLoggerConfig = config.LoggerConfig.map { nodeConfig in
            SwiftCommon.LoggerConfig(
                level: SwiftCommon.LogLevel(rawValue: nodeConfig.defaultLevel.rawValue) ?? .info,
                includeTimestamp: true,
                includeComponent: true,
                includeContext: true
            )
        }
        let logger = RunarLogger.root(component: .node, config: commonLoggerConfig)
        let serviceRegistry = ServiceRegistry(logger: logger)

        // Extract the key manager from config
        guard let keysManager = config.getKeyManager() else {
            throw NodeError.missingKeyManager("Failed to load node credentials.")
        }

        let nodePublicKey = try await keysManager.getNodePublicKey()

        let nodeId = try await keysManager.getCompactId(for: nodePublicKey)
        // logger.setContext(nodeId) // RunarLogger doesn't have setContext method

        logger.trace("Successfully loaded existing node credentials.")

        let localNodeInfo = NodeInfo(
            nodePublicKey: nodePublicKey,
            networkIds: networkIds,
            addresses: [],
            nodeMetadata: NodeMetadata(services: [], subscriptions: []),
            version: 0
        )

        let node = Node(
            debounceTask: nil as Task<Void, Never>?,
            networkId: defaultNetworkId,
            networkIds: networkIds,
            nodeId: nodeId,
            nodePublicKey: nodePublicKey,
            config: config,
            serviceRegistry: serviceRegistry,
            remoteNodeInfo: ShardedConcurrentMap<String, NodeInfo>(),
            discoverySeenTimes: ShardedConcurrentMap<String, Date>(),
            logger: logger,
            running: false,
            supportsNetworking: networkingEnabled,
            networkTransport: nil as NodeTransport?,
            networkDiscoveryProviders: nil as [NodeDiscovery]?,
            loadBalancer: RoundRobinLoadBalancer(),
            systemLabelConfig: config.labelResolverConfig,
            labelResolverCache: ResolverCache(capacity: 1000, ttlSeconds: 300),
            registryVersion: 0,
            keysManager: keysManager,
            serviceTasks: [],
            localNodeInfo: localNodeInfo,
            retainedEvents: ShardedConcurrentMap<String, RetainedDeque>(),
            retainedIndex: PathTrie<String>()
        )

        // Register the registry service
        let registryService = RegistryService(
            logger: logger,
            registryDelegate: node
        )
        try await node.addService(registryService)

        let keysService = KeysService(
            logger: logger,
            nodeDelegate: node
        )
        try await node.addService(keysService)

        return node
    }

    // MARK: - Private Initializer

    private init(
        debounceTask: Task<Void, Never>?,
        networkId: String,
        networkIds: [String],
        nodeId: String,
        nodePublicKey: Data,
        config: NodeConfig,
        serviceRegistry: ServiceRegistry,
        remoteNodeInfo: ShardedConcurrentMap<String, NodeInfo>,
        discoverySeenTimes: ShardedConcurrentMap<String, Date>,
        logger: RunarLogger,
        running: Bool,
        supportsNetworking: Bool,
        networkTransport: (any NodeTransport)?,
        networkDiscoveryProviders: [NodeDiscovery]?,
        loadBalancer: RoundRobinLoadBalancer,
        systemLabelConfig: LabelResolverConfig,
        labelResolverCache: ResolverCache,
        registryVersion: Int64,
        keysManager: FFIKeys,
        serviceTasks: [ServiceTask],
        localNodeInfo: NodeInfo,
        retainedEvents: ShardedConcurrentMap<String, RetainedDeque>,
        retainedIndex: PathTrie<String>
    ) {
        self.debounceTask = debounceTask
        self.networkId = networkId
        self.networkIds = networkIds
        self.nodeId = nodeId
        self.nodePublicKey = nodePublicKey
        self.config = config
        self.serviceRegistry = serviceRegistry
        self.remoteNodeInfo = remoteNodeInfo
        self.discoverySeenTimes = discoverySeenTimes
        self.logger = logger
        self.running = running
        self.supportsNetworking = supportsNetworking
        self.networkTransport = networkTransport
        self.networkDiscoveryProviders = networkDiscoveryProviders
        self.loadBalancer = loadBalancer
        self.systemLabelConfig = systemLabelConfig
        self.labelResolverCache = labelResolverCache
        self.registryVersion = registryVersion
        self.keysManager = keysManager
        self.serviceTasks = serviceTasks
        self.localNodeInfo = localNodeInfo
        self.retainedEvents = retainedEvents
        self.retainedIndex = retainedIndex
    }

    // MARK: - Core Methods

    /// Get or create resolver using node's cache instance
    private func getOrCreateResolver(userProfileKeys: [Data]) throws -> LabelResolver {
        try LabelResolver.createContextResolver(
            systemConfig: systemLabelConfig,
            userProfilePublicKeys: userProfileKeys
        )
    }

    /// Publish an event with optional retention
    ///
    /// This method publishes an event to local subscribers and optionally retains it
    /// for late subscribers based on the publish options.
    ///
    /// # Arguments
    ///
    /// * `topic` - The topic to publish to
    /// * `data` - The event data to publish
    /// * `options` - Optional publish options including retention settings
    ///
    /// # Process
    ///
    /// 1. Notify local subscribers immediately
    /// 2. If retention is configured, store the event in retained events
    /// 3. Update the retained index for wildcard lookups
    /// 4. Broadcast to remote nodes if requested
    ///
    /// # Examples
    ///
    /// ```swift
    /// // Publish without retention
    /// try await node.publish("my-topic", data: AnyValue.string("hello"))
    ///
    /// // Publish with retention
    /// try await node.publish("my-topic", data: AnyValue.string("hello"),
    ///                        options: PublishOptions(retainFor: 60))
    /// ```
    public func publish(topic: String, data: AnyValue?, options: PublishOptions? = nil) async throws {
        // Parse topic path
        let topicPath = try TopicPath(networkId: networkId, segments: topic.split(separator: "/").map(String.init))

        // Notify local subscribers first
        logger.debug("Publishing event to topic: \(topic) with data: \(String(describing: data))")
        await serviceRegistry.publish(topic: topic, data: data, networkId: networkId)

        let publishOptions = options ?? PublishOptions()

        // Retain event locally if configured
        if let retainFor = publishOptions.retainFor {
            let key = topicPath.rawPath
            let now = Date()

            // Get or create retained deque for this topic
            let deque: RetainedDeque
            if let existingDeque = await retainedEvents.get(key) {
                deque = existingDeque
            } else {
                deque = RetainedDeque(capacity: RetainedDeque.maxRetainPerTopic, ttlSeconds: retainFor)
                _ = await retainedEvents.insert(deque, for: key)
            }

            // Append the event to the deque
            await deque.append(timestamp: now, data: data)

            // Update retained index for wildcard lookups
            retainedIndex.setValue(topic: topicPath, content: key)

            logger.debug("Retained event for topic '\(key)' with TTL \(retainFor)s")
        }

        // Broadcast to remote nodes if requested and networking is enabled
        if publishOptions.broadcast, supportsNetworking {
            // TODO: Implement remote broadcasting when networking is available
            logger.debug("Remote broadcasting not yet implemented")
        }
    }

    /// Subscribe to events with optional includePast support
    ///
    /// This method subscribes to events on a topic and optionally delivers
    /// retained events that occurred within the specified lookback window.
    ///
    /// # Arguments
    ///
    /// * `topic` - The topic to subscribe to
    /// * `callback` - The event handler callback
    /// * `options` - Optional subscription options including includePast
    ///
    /// # Returns
    ///
    /// Returns a subscription ID that can be used to unsubscribe
    ///
    /// # Examples
    ///
    /// ```swift
    /// // Subscribe without includePast
    /// let subscriptionId = try await node.subscribe("my-topic") { data in
    ///     print("Received event: \(data)")
    /// }
    ///
    /// // Subscribe with includePast
    /// let subscriptionId = try await node.subscribe("my-topic",
    ///     options: EventRegistrationOptions(includePast: 60)) { data in
    ///     print("Received event: \(data)")
    /// }
    /// ```
    public func subscribe(topic: String, options: EventRegistrationOptions? = nil, callback: @escaping EventHandler) async throws -> String {
        // Parse topic path
        let topicPath = try TopicPath(networkId: networkId, segments: topic.split(separator: "/").map(String.init))

        // Register the subscription with the correct networkId
        let subscriptionId = try await serviceRegistry.subscribeToEvents(
            networkId: networkId,
            servicePath: topic,
            handler: callback
        )

        // Deliver past events if requested
        if let includePast = options?.includePast {
            let now = Date()
            let cutoff = now.addingTimeInterval(-includePast)

            // Find matching topics for wildcard patterns
            let matchedKeys: [String]
            if topicPath.isPattern {
                // For now, just check exact topic since wildcard matching is not implemented
                let exactKey = topicPath.rawPath
                if await retainedEvents.get(exactKey) != nil {
                    matchedKeys = [exactKey]
                } else {
                    matchedKeys = []
                }
            } else {
                // For exact topics, check if we have retained events
                let exactKey = topicPath.rawPath
                if await retainedEvents.get(exactKey) != nil {
                    matchedKeys = [exactKey]
                } else {
                    matchedKeys = []
                }
            }

            // Find the newest retained event within the cutoff time
            var newestEvent: (date: Date, data: AnyValue?, key: String)?

            for key in matchedKeys {
                if let deque = await retainedEvents.get(key) {
                    let events = await deque.snapshot()
                    for event in events.reversed() { // Check newest first
                        if event.timestamp >= cutoff {
                            if newestEvent == nil || event.timestamp > newestEvent!.date {
                                newestEvent = (event.timestamp, event.data, key)
                            }
                            break // Found the newest event for this topic
                        }
                    }
                }
            }

            // Deliver the newest retained event if found
            if let (_, data, _) = newestEvent {
                logger.debug("Delivering retained event to new subscriber for topic '\(topic)'")
                await callback(data)
            } else {
                logger.debug("No retained event found for topic '\(topic)' within lookback window")
            }
        }

        return subscriptionId
    }

    /// Add a service to this node.
    ///
    /// This method registers a service with the node, making its actions available
    /// for requests and allowing it to receive events. The service is initialized
    /// but not started - services are started when the node is started.
    ///
    /// # Arguments
    ///
    /// * `service` - The service to register, must implement `AbstractService`
    ///
    /// # Process
    ///
    /// 1. Validates the service path and creates a topic path
    /// 2. Initializes the service with a lifecycle context
    /// 3. Creates a service entry and registers it with the service registry
    /// 4. Updates the service state to `Initialized`
    /// 5. If the node is already running, starts the service immediately
    ///
    /// # Examples
    ///
    /// ```swift
    /// let service = MyService()
    /// try await node.addService(service)
    /// ```
    public func addService(_ service: AbstractService) async throws {
        // Set the service's network ID
        service.setNetworkId(networkId)

        let servicePath = service.path
        let serviceName = service.name

        logger.trace("Adding service '\(serviceName)' to node using path \(servicePath)")

        // Create a proper topic path for the service (matching Rust pattern)
        let serviceTopic = try TopicPath(networkId: networkId, segments: servicePath.split(separator: "/").map(String.init))

        // Create a lifecycle context for initialization (matching Rust pattern)
        let initContext = LifecycleContext(
            networkId: networkId,
            servicePath: servicePath,
            config: nil,
            logger: logger,
            nodeDelegate: self
        )

        // Initialize the service using the context (matching Rust pattern)
        do {
            try await service.initService(initContext)
        } catch {
            logger.error("Failed to initialize service: \(serviceName), error: \(error)")
            // Update service state to error (matching Rust pattern)
            try await serviceRegistry.updateLocalServiceState(
                servicePath: serviceTopic.rawPath,
                newState: ServiceState.error
            )
            // Publish error event (matching Rust pattern)
            try await publish(
                topic: "$registry/services/\(servicePath)/state/error",
                data: AnyValue.primitive(serviceTopic.rawPath),
                options: PublishOptions(retainFor: 10.0)
            )
            throw NodeError.serviceInitializationFailed("Failed to initialize service: \(error)")
        }

        // Update service state to initialized (matching Rust pattern)
        try await serviceRegistry.updateLocalServiceState(
            servicePath: serviceTopic.rawPath,
            newState: ServiceState.initialized
        )

        // Publish initialized event (matching Rust pattern)
        try await publish(
            topic: "$registry/services/\(servicePath)/state/initialized",
            data: AnyValue.primitive(serviceTopic.rawPath),
            options: PublishOptions(retainFor: 10.0)
        )

        // Service initialized successfully, create the ServiceEntry and register it (matching Rust pattern)
        let now = UInt64(Date().timeIntervalSince1970)

        let serviceEntry = ServiceEntry(
            serviceTopic: serviceTopic,
            service: service,
            state: ServiceState.initialized,
            registrationTime: now,
            lastStartTime: nil // Will be set when the service is started
        )

        // Register the service with the registry (matching Rust pattern)
        try await serviceRegistry.registerLocalService(serviceEntry)
        logger.trace("🔍 Service registered successfully: \(servicePath)")

        // Update the transport with the new NodeInfo if the node is already running
        // If the node is not yet started, the transport will be created with the current NodeInfo when it starts
        if isRunning {
            print("🔍 SERVICE: Node is running, updating transport with new NodeInfo...")
            await updateTransportNodeInfo()
        } else {
            print("🔍 SERVICE: Node not yet started, transport will be created with current NodeInfo when started")
        }

        // If the node is already running, start the service immediately (matching Rust pattern)
        if isRunning {
            try await startService(serviceTopic: serviceTopic, serviceEntry: serviceEntry)
        }
    }

    /// Start a specific service (matching Rust pattern)
    private func startService(serviceTopic: TopicPath, serviceEntry: ServiceEntry) async throws {
        let servicePath = serviceEntry.service.path
        let serviceName = serviceEntry.service.name

        logger.trace("Starting service '\(serviceName)' with path \(servicePath)")

        // Create lifecycle context for starting
        let startContext = LifecycleContext(
            topicPath: serviceTopic,
            nodeDelegate: self,
            logger: logger
        )

        // Start the service
        do {
            // First initialize the service (registers action handlers)
            try await serviceEntry.service.initService(startContext)
            try await serviceRegistry.updateLocalServiceState(
                servicePath: serviceTopic.rawPath,
                newState: ServiceState.initialized
            )

            // Then start the service (begins active operations)
            try await serviceEntry.service.start(startContext)

            // Update service state to running
            try await serviceRegistry.updateLocalServiceState(
                servicePath: serviceTopic.rawPath,
                newState: ServiceState.running
            )

            // Note: We can't update the ServiceEntry directly since it's a struct,
            // but the state is tracked in the registry

            logger.trace("Service '\(serviceName)' started successfully")
        } catch {
            logger.error("Failed to start service '\(serviceName)': \(error)")

            // Update service state to error
            try await serviceRegistry.updateLocalServiceState(
                servicePath: serviceTopic.rawPath,
                newState: ServiceState.error
            )

            // Publish error event
            try await publish(
                topic: "$registry/services/\(servicePath)/state/error",
                data: AnyValue.primitive(serviceTopic.rawPath),
                options: PublishOptions(retainFor: 10.0)
            )

            throw NodeError.serviceInitializationFailed("Failed to start service '\(serviceName)': \(error)")
        }
    }

    /// Start the node and all its services.
    ///
    /// This method starts the node, initializes all registered services,
    /// and begins network operations if networking is enabled.
    ///
    /// # Process
    ///
    /// 1. Starts all registered services
    /// 2. Initializes network transport if networking is enabled
    /// 3. Starts discovery providers if configured
    /// 4. Sets the node as running
    ///
    /// # Examples
    ///
    /// ```swift
    /// try await node.start()
    /// ```
    public func start() async throws {
        logger.trace("Node started networkId=\(networkId)")

        // Start all registered services
        print("🔍 DEBUG: About to start all local services for networkId: \(networkId)")
        try await serviceRegistry.startAllServices(networkId: networkId)
        print("🔍 DEBUG: All local services started successfully")

        // Initialize network transport if networking is enabled
        if supportsNetworking {
            try await initializeNetworkTransport()

            // Update the transport with current NodeInfo after it's created
            // This ensures the transport has the latest NodeInfo with all services
            print("🔍 START: Updating transport with current NodeInfo after creation...")
            await updateTransportNodeInfo()
        }

        // Set the node as running
        running = true

        logger.trace("Node is now running")
    }

    /// Stop the node and all its services.
    ///
    /// This method stops the node, shuts down all services,
    /// and cleans up network resources.
    ///
    /// # Process
    ///
    /// 1. Stops all registered services
    /// 2. Shuts down network transport
    /// 3. Cleans up discovery providers
    /// 4. Sets the node as not running
    ///
    /// # Examples
    ///
    /// ```swift
    /// await node.stop()
    /// ```
    public func stop() async {
        logger.trace("Node stopped")

        // Stop all registered services
        await serviceRegistry.stopAllServices()

        // Shutdown network transport
        networkTransport = nil

        // Set the node as not running
        running = false

        logger.trace("Node has been stopped")
    }

    /// Wait for all services to start
    ///
    /// This method waits for all registered services to complete their startup process.
    public func waitForServicesToStart() async throws {
        logger.trace("Waiting for services to start")

        // Wait for all services to be in running state
        let services = serviceRegistry.getAllEntries(networkId: networkId)
        for serviceEntry in services {
            // Wait for service to be in running state
            var attempts = 0
            let maxAttempts = 100 // 10 seconds with 100ms intervals

            while attempts < maxAttempts {
                if let state = await serviceRegistry.getLocalServiceState(servicePath: serviceEntry.serviceTopic) {
                    if state == .running {
                        break
                    }
                }

                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                attempts += 1
            }

            if attempts >= maxAttempts {
                logger.warning("Service \(serviceEntry.serviceTopic.rawPath) did not start within timeout")
            }
        }

        logger.trace("All services started")
    }

    /// Make a request to a service
    ///
    /// This method forwards the request to the ServiceRegistry for processing.
    public func request(_ path: String, payload: AnyValue?, networkId: String?) async throws -> AnyValue {
        let actualNetworkId = networkId ?? self.networkId
        return try await serviceRegistry.request(path, payload: payload, networkId: actualNetworkId)
    }

    // MARK: - Private Helper Methods

    /// Initialize network transport for remote communication
    private func initializeNetworkTransport() async throws {
        print("🔍 NETWORKING: Starting networking components...")
        logger.trace("Starting networking components...")

        guard supportsNetworking else {
            print("🔍 NETWORKING: Networking is disabled, skipping network initialization")
            logger.trace("Networking is disabled, skipping network initialization")
            return
        }

        guard let networkConfig = config.networkConfig else {
            throw NodeError.invalidConfiguration("Network configuration is required")
        }

        print("🔍 NETWORKING: Network config: \(networkConfig)")
        logger.trace("Network config: \(networkConfig)")

        // Initialize the network transport
        if networkTransport == nil {
            print("🔍 NETWORKING: Initializing network transport...")
            logger.trace("Initializing network transport...")

            // Create network transport using the factory pattern based on transport_type
            let transport = try await createTransport(networkConfig: networkConfig)

            print("🔍 NETWORKING: Starting transport...")
            try await transport.start()
            print("🔍 NETWORKING: Transport started successfully")

            // Store the transport
            networkTransport = transport
            
            // Note: Local peer info will be updated after discovery providers are created
        } else {
            print("🔍 NETWORKING: Transport already initialized, skipping")
        }

        // Update local node info after transport is initialized
        _ = await getLocalNodeInfo()

        // Initialize discovery if enabled
        if let discoveryOptions = networkConfig.discoveryOptions {
            print("🔍 NETWORKING: Initializing node discovery providers...")
            logger.trace("Initializing node discovery providers...")

            // Check if any providers are configured
            if networkConfig.discoveryProviders.isEmpty {
                throw NodeError.invalidConfiguration("No discovery providers configured")
            }

            print("🔍 NETWORKING: Found \(networkConfig.discoveryProviders.count) discovery providers")
            var discoveryProviders: [NodeDiscovery] = []

            // Iterate through all discovery providers and initialize each one
            for providerConfig in networkConfig.discoveryProviders {
                print("🔍 NETWORKING: Creating discovery provider: \(providerConfig)")
                logger.trace("Creating discovery provider: \(providerConfig)")

                // Create discovery provider instance
                let discoveryProvider = try await createDiscoveryProvider(
                    providerConfig: providerConfig,
                    discoveryOptions: discoveryOptions
                )

                // Start announcing on this provider
                print("🔍 NETWORKING: Starting to announce on discovery provider")
                logger.trace("Starting to announce on discovery provider")
                try await discoveryProvider.start()
                print("🔍 NETWORKING: Discovery provider started successfully")

                discoveryProviders.append(discoveryProvider)
            }

            // Store the discovery providers
            networkDiscoveryProviders = discoveryProviders
            print("🔍 NETWORKING: Stored \(discoveryProviders.count) discovery providers")

            // CRITICAL: Update local peer info for discovery announcements
            // This must be done after discovery providers are created and started
            print("🔍 DISCOVERY: About to update local peer info for discovery announcements")
            try await updateLocalPeerInfoForDiscoveryAfterTransportStart()
            print("🔍 DISCOVERY: Completed updating local peer info for discovery announcements")

            // Update the transport with the current NodeInfo (including any services added before networking started)
            print("🔍 NETWORKING: Updating transport with current NodeInfo...")
            _ = await getLocalNodeInfo()
            print("🔍 NETWORKING: Transport updated with current NodeInfo")
        } else {
            print("🔍 NETWORKING: No discovery options configured, skipping discovery")
        }

        print("🔍 NETWORKING: Networking components started successfully")
        logger.trace("Networking components started successfully")
    }

    /// Create network transport based on configuration
    private func createTransport(networkConfig: NetworkConfig) async throws -> NodeTransport {
        print("🔍 TRANSPORT: Creating QUIC transport")
        logger.trace("Creating QUIC transport")

        // Get the current NodeInfo (this is just a getter, no transport update)
        let currentNodeInfo = await getLocalNodeInfo()
        print("🔍 TRANSPORT: Got current NodeInfo with \(currentNodeInfo.nodeMetadata.services.count) services")

        // Note: The transport will be created with transport-scoped NodeInfo storage
        // The initial NodeInfo will be set when the transport is created
        print("🔍 TRANSPORT: Transport will use transport-scoped NodeInfo storage")

        // Create transport options matching Rust implementation
        let transportOptions = QuicTransportOptions(
            requestTimeoutSeconds: UInt64(config.requestTimeoutMs / 1000),
            bindAddr: networkConfig.bindAddress ?? "127.0.0.1:0"
        )
        print("🔍 TRANSPORT: Transport options: \(transportOptions)")

        // Create callbacks for network events
        print("🔍 TRANSPORT: Creating transport callbacks")
        let callbacks = TransportCallbacks(
            peerConnectedCallback: { [weak self] peerNodeId, nodeInfo in
                Task { @MainActor in
                    print("🔍 HANDSHAKE: Peer connected callback triggered for peer: \(peerNodeId) at \(Date())")
                    print("🔍 HANDSHAKE: NodeInfo received: \(nodeInfo)")
                    print("🔍 HANDSHAKE: Raw FFI NodeInfo - services: \(nodeInfo.nodeMetadata.services.count), subscriptions: \(nodeInfo.nodeMetadata.subscriptions.count)")
                    print("🔍 HANDSHAKE: This NodeInfo was sent by the peer during handshake - it should contain the peer's services")
                    for (index, service) in nodeInfo.nodeMetadata.services.enumerated() {
                        print("🔍 HANDSHAKE: Service \(index): path=\(service.servicePath), name=\(service.name)")
                    }

                    // Convert SwiftFFI.NodeInfo to SwiftNode.NodeInfo
                    let swiftNodeInfo = NodeInfo(
                        nodePublicKey: nodeInfo.nodePublicKey,
                        networkIds: nodeInfo.networkIds,
                        addresses: nodeInfo.addresses,
                        nodeMetadata: {
                            let ffiMetadata = nodeInfo.nodeMetadata
                            print("🔍 HANDSHAKE: Converting FFI metadata: \(ffiMetadata.services.count) services, \(ffiMetadata.subscriptions.count) subscriptions")
                            return NodeMetadata(
                                services: ffiMetadata.services.map { ffiService in
                                    "\(ffiService.servicePath)/\(ffiService.name)"
                                },
                                subscriptions: ffiMetadata.subscriptions.map { ffiSubscription in
                                    ffiSubscription.path
                                }
                            )
                        }(),
                        version: nodeInfo.version
                    )
                    print("🔍 HANDSHAKE: Converted NodeInfo: \(swiftNodeInfo)")
                    print("🔍 HANDSHAKE: Converted services: \(swiftNodeInfo.nodeMetadata.services)")
                    await self?.handlePeerConnected(peerNodeId: peerNodeId, nodeInfo: swiftNodeInfo)
                }
            },
            peerDisconnectedCallback: { [weak self] peerNodeId in
                Task { @MainActor in
                    await self?.handlePeerDisconnected(peerNodeId: peerNodeId)
                }
            },
            requestCallback: { [weak self] _, path, payload, sourcePeerId, correlationId in
                // Create NetworkMessage from the callback parameters
                let payloadItem = NetworkMessagePayloadItem(
                    path: path,
                    payloadBytes: payload,
                    correlationId: correlationId ?? "",
                    networkPublicKey: nil, // Will be set during processing
                    profilePublicKeys: [] // Will be set during processing
                )

                let networkMessage = NetworkMessage(
                    sourceNodeId: sourcePeerId,
                    destinationNodeId: self?.nodeId ?? "",
                    messageType: 4, // MESSAGE_TYPE_REQUEST
                    payload: payloadItem
                )

                // Process the network request asynchronously (matching Rust pattern)
                // Always return a NetworkMessage - if self is nil, create a default error response
                guard let self = self else {
                    // Create a default error response when self is nil
                    return NetworkMessage(
                        sourceNodeId: sourcePeerId,
                        destinationNodeId: "",
                        messageType: 5, // MESSAGE_TYPE_RESPONSE
                        payload: NetworkMessagePayloadItem(
                            path: path,
                            payloadBytes: Data("{\"error\": true, \"message\": \"Node not available\"}".utf8),
                            correlationId: correlationId ?? "",
                            networkPublicKey: nil,
                            profilePublicKeys: []
                        )
                    )
                }
                
                // Use async request handling (matching Rust pattern)
                // Now that callbacks are async, we can properly handle async work
                return await self.handleNetworkRequestAsync(networkMessage)
            },
            eventCallback: { [weak self] requestId, path, payload, sourcePeerId, correlationId in
                Task { @MainActor in
                    await self?.handleNetworkEvent(
                        requestId: requestId,
                        path: path,
                        payload: payload,
                        sourcePeerId: sourcePeerId,
                        correlationId: correlationId
                    )
                }
            }
        )

        // Convert SwiftNode.NodeInfo to SwiftFFI.NodeInfo
        let ffiNodeInfo = convertToFFINodeInfo(currentNodeInfo)

        // Create the QuicTransport using the key manager
        let keyManager: FFIKeys = try config.getKeyManager()
        let transport = try await QuicTransport.create(
            keys: keyManager,
            nodeInfo: ffiNodeInfo,
            options: transportOptions,
            callbacks: callbacks,
            logger: logger
        )

        print("🔍 TRANSPORT: QUIC transport created successfully")
        logger.trace("QUIC transport created successfully")
        return transport
    }

    /// Create discovery provider based on configuration
    private func createDiscoveryProvider(
        providerConfig _: DiscoveryProviderConfig,
        discoveryOptions: SwiftFFI.DiscoveryOptions
    ) async throws -> NodeDiscovery {
        logger.trace("🔍 Creating real discovery provider with options: \(discoveryOptions)")

        // Encode discovery options to CBOR
        let encoder = CodableCBOREncoder()
        let optionsCbor = try encoder.encode(discoveryOptions)
        logger.trace("🔍 Discovery options encoded to CBOR: \(optionsCbor.count) bytes")

        // Create discovery handle using the key manager
        guard let keyManager = config.getKeyManager() else {
            throw NodeError.missingKeyManager("Key manager not set in configuration")
        }
        logger.trace("🔍 Creating discovery handle with key manager")
        let discoveryHandle = try await keyManager.createDiscoveryHandle(optionsCbor: optionsCbor)
        logger.trace("🔍 Discovery handle created successfully")

        // Initialize discovery
        logger.trace("🔍 Initializing discovery with options")
        try await discoveryHandle.initialize(optionsCbor: optionsCbor)
        logger.trace("🔍 Discovery initialized successfully")

        // Create discovery callbacks for handling discovery events
        let discoveryCallbacks = DiscoveryCallbacks(
            discoveredCallback: { [weak self] peerInfo in
                Task { @MainActor in
                    await self?.handlePeerDiscovered(peerInfo: peerInfo)
                }
            },
            updatedCallback: { [weak self] peerInfo in
                Task { @MainActor in
                    await self?.handlePeerUpdated(peerInfo: peerInfo)
                }
            },
            lostCallback: { [weak self] nodeId in
                Task { @MainActor in
                    await self?.handlePeerLost(nodeId: nodeId)
                }
            }
        )

        // Create and return discovery provider
        logger.trace("🔍 Creating Discovery instance")
        let discoveryProvider = Discovery(discoveryHandle: discoveryHandle, logger: logger)
        
        // Set the callbacks on the discovery provider
        await discoveryProvider.setCallbacks(discoveryCallbacks)
        
        // Note: Local peer info will be updated after transport is started
        // This is because we need the transport's local address
        
        return discoveryProvider
    }

    /// Update local peer info for discovery announcements after transport is started
    private func updateLocalPeerInfoForDiscoveryAfterTransportStart() async throws {
        logger.trace("🔍 DISCOVERY: Updating local peer info for discovery announcements after transport start")
        print("🔍 DISCOVERY: Updating local peer info for discovery announcements after transport start")
        
        // Get the local transport address
        guard let transport = networkTransport else {
            logger.warning("🔍 DISCOVERY: No transport available, cannot get local address")
            print("🔍 DISCOVERY: No transport available, cannot get local address")
            return
        }
        
        // Get key manager
        guard let keyManager = config.getKeyManager() else {
            logger.warning("🔍 DISCOVERY: No key manager available")
            print("🔍 DISCOVERY: No key manager available")
            return
        }
        
        do {
            // Get local address from transport
            let localAddr = try await transport.localAddr()
            logger.trace("🔍 DISCOVERY: Local address: \(localAddr)")
            print("🔍 DISCOVERY: Local address: \(localAddr)")
            
            // Get node public key from key manager
            let nodePublicKey = try await keyManager.getNodePublicKey()
            logger.trace("🔍 DISCOVERY: Node public key: \(nodePublicKey.count) bytes")
            print("🔍 DISCOVERY: Node public key: \(nodePublicKey.count) bytes")
            
            // Create peer info
            let peerInfo = SwiftFFI.PeerInfo(
                publicKey: nodePublicKey,
                addresses: [localAddr]
            )
            print("🔍 DISCOVERY: Created PeerInfo with address: \(localAddr)")
            
            // Encode peer info to CBOR
            let encoder = CodableCBOREncoder()
            let peerInfoCbor = try encoder.encode(peerInfo)
            logger.trace("🔍 DISCOVERY: Peer info encoded to CBOR: \(peerInfoCbor.count) bytes")
            print("🔍 DISCOVERY: Peer info encoded to CBOR: \(peerInfoCbor.count) bytes")
            
            // Update all discovery providers with the peer info
            if let discoveryProviders = networkDiscoveryProviders {
                print("🔍 DISCOVERY: Found \(discoveryProviders.count) discovery providers to update")
                for (index, discoveryProvider) in discoveryProviders.enumerated() {
                    print("🔍 DISCOVERY: Updating discovery provider \(index + 1) of \(discoveryProviders.count)")
                    if let discovery = discoveryProvider as? Discovery {
                        print("🔍 DISCOVERY: Calling updateLocalPeerInfo on discovery provider \(index + 1)")
                        try await discovery.updateLocalPeerInfo(peerInfoCbor: peerInfoCbor)
                        logger.trace("🔍 DISCOVERY: Updated peer info for discovery provider")
                        print("🔍 DISCOVERY: Successfully updated peer info for discovery provider \(index + 1)")
                    } else {
                        print("🔍 DISCOVERY: Discovery provider \(index + 1) is not a Discovery instance")
                    }
                }
            } else {
                print("🔍 DISCOVERY: No discovery providers available (networkDiscoveryProviders is nil)")
            }
            
            logger.trace("🔍 DISCOVERY: Local peer info updated successfully for all discovery providers")
            print("🔍 DISCOVERY: Local peer info updated successfully for all discovery providers")
            
        } catch {
            logger.error("🔍 DISCOVERY: Failed to update local peer info: \(error)")
            print("🔍 DISCOVERY: Failed to update local peer info: \(error)")
            throw error
        }
    }

    /// Get local node information with current service metadata (GETTER ONLY)
    private func getLocalNodeInfo() async -> NodeInfo {
        // Get current services from the service registry
        let currentServices = serviceRegistry.getLocalServices()
        let servicePaths = Array(currentServices.keys).map { $0.asString() }

        print("🔍 DEBUG: Found \(currentServices.count) local services")
        for (topicPath, serviceEntry) in currentServices {
            print("🔍 DEBUG: Service: \(topicPath.asString()) -> \(serviceEntry.service.name)")
        }

        // Get current subscriptions from the service registry (currently returns empty array)
        let currentSubscriptions = try? await serviceRegistry.getAllSubscriptions(includeInternalServices: false)
        let subscriptionPaths = currentSubscriptions?.map(\.path) ?? []

        // Create updated NodeInfo with current service metadata
        let updatedNodeInfo = NodeInfo(
            nodePublicKey: localNodeInfo.nodePublicKey,
            networkIds: localNodeInfo.networkIds,
            addresses: localNodeInfo.addresses,
            nodeMetadata: NodeMetadata(
                services: servicePaths,
                subscriptions: subscriptionPaths
            ),
            version: localNodeInfo.version
        )

        print("🔍 DEBUG: Updated NodeInfo with \(servicePaths.count) services and \(subscriptionPaths.count) subscriptions")
        logger.trace("🔍 Updated NodeInfo with \(servicePaths.count) services and \(subscriptionPaths.count) subscriptions")

        return updatedNodeInfo
    }

    /// Update the transport with current NodeInfo (SETTER ONLY)
    private func updateTransportNodeInfo() async {
        guard let transport = networkTransport as? QuicTransport else {
            print("🔍 DEBUG: No transport found (networkTransport is nil or not QuicTransport)")
            return
        }

        print("🔍 DEBUG: Transport found, updating with NodeInfo...")
        do {
            // Get current NodeInfo
            let currentNodeInfo = await getLocalNodeInfo()

            // Convert SwiftNode.NodeInfo to SwiftFFI.NodeInfo
            let ffiNodeInfo = convertToFFINodeInfo(currentNodeInfo)

            print("🔍 DEBUG: Calling transport.updateLocalNodeInfo()... at \(Date())")
            print("🔍 DEBUG: About to send NodeInfo with \(ffiNodeInfo.nodeMetadata.services.count) services to transport")
            print("🔍 DEBUG: This should update the transport-scoped NodeInfo storage for handshakes")
            try await transport.updateLocalNodeInfo(nodeInfo: ffiNodeInfo)
            print("🔍 DEBUG: Successfully updated transport with new NodeInfo at \(Date())")
            print("🔍 DEBUG: The transport-scoped NodeInfo storage should now contain \(ffiNodeInfo.nodeMetadata.services.count) services")
            logger.trace("🔍 Successfully updated transport with new NodeInfo")
        } catch {
            print("🔍 DEBUG: Failed to update transport with new NodeInfo: \(error)")
            logger.error("🔍 Failed to update transport with new NodeInfo: \(error)")
        }
    }

    /// Convert SwiftNode.NodeInfo to SwiftFFI.NodeInfo
    private func convertToFFINodeInfo(_ nodeInfo: NodeInfo) -> SwiftFFI.NodeInfo {
        SwiftFFI.NodeInfo(
            nodePublicKey: nodeInfo.nodePublicKey,
            networkIds: nodeInfo.networkIds,
            addresses: nodeInfo.addresses,
            nodeMetadata: SwiftFFI.NodeMetadata(
                services: nodeInfo.nodeMetadata.services.map { servicePath in
                    // Parse the service path to extract service name and path
                    let components = servicePath.split(separator: "/")
                    let serviceName = components.last?.description ?? servicePath
                    let servicePath = components.dropLast().joined(separator: "/")
                    return SwiftFFI.ServiceMetadata(
                        networkId: networkId,
                        servicePath: servicePath,
                        name: serviceName,
                        version: "1.0.0",
                        description: "Service",
                        actions: [],
                        registrationTime: 0,
                        lastStartTime: nil
                    )
                },
                subscriptions: nodeInfo.nodeMetadata.subscriptions.map { subscriptionPath in
                    SwiftFFI.SubscriptionMetadata(path: subscriptionPath)
                }
            ),
            version: nodeInfo.version
        )
    }

    /// Compact ID generation from public key
    private func compactId(_ publicKey: Data) -> String {
        // Generate a compact ID from the public key
        // This should match the Rust implementation
        publicKey.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Get or create resolver for user profile keys
    /// Matches Rust: get_or_create_resolver
    private func getOrCreateResolver(_: [Data]) throws -> LabelResolver {
        // TODO: Implement proper resolver cache when ResolverCache is available
        // For now, create a basic resolver with empty mapping
        LabelResolver(mapping: [:])
    }

    // MARK: - Network Message Handling

    /// Handle network request synchronously (required by FFI transport)
    private nonisolated func handleNetworkRequestSync(_ message: NetworkMessage) -> NetworkMessage {
        logger.trace("[handle_network_request] path: \(message.payload.path) correlation_id: \(message.payload.correlationId) profile_public_keys size: \(message.payload.profilePublicKeys.count)")

        // Parse topic path to get network ID
        guard let topicPath = try? TopicPath.parse(message.payload.path) else {
            logger.error("Failed to parse topic path: \(message.payload.path)")
            return createErrorResponseSync(originalMessage: message, error: "Failed to parse topic path")
        }

        let networkId = topicPath.networkId
        let profilePublicKeys = message.payload.profilePublicKeys

        // 1. Deserialize the request payload to AnyValue (matching Rust pattern)
        let requestValue: AnyValue
        do {
            requestValue = try AnyValue.deserialize(message.payload.payloadBytes)
        } catch {
            logger.error("Failed to deserialize request payload: \(error)")
            return createErrorResponseSync(originalMessage: message, error: "Failed to deserialize request payload")
        }

        // 2. Process request locally (matching Rust pattern)
        // Note: This is a synchronous method, so we need to handle the async service registry call
        // For now, we'll create a proper error response and log that async handling is needed
        logger.warning("Synchronous request handling not fully implemented - service registry calls are async")
        
        // 3. Create proper error response using AnyValue (matching Rust pattern)
        let errorValue = AnyValue.map([
            "error": AnyValue.primitive(true),
            "message": AnyValue.primitive("Synchronous service registry calls not yet implemented")
        ])
        
        // 4. Create serialization context (matching Rust pattern)
        // Note: This is a simplified version - in practice, we'd need proper context creation
        let serializationContext: SerializationContext? = nil // TODO: Create proper context
        
        // 5. Serialize response with context (matching Rust pattern)
        // Note: This is a synchronous method, so we need to handle async serialization
        // For now, we'll use a simple approach until we can properly bridge async/sync
        let responseBytes: Data
        do {
            // TODO: Implement proper async/sync bridging for serialization
            // For now, create a simple fallback
            let errorDict: [String: Any] = [
                "error": true,
                "message": "Synchronous service registry calls not yet implemented"
            ]
            responseBytes = try JSONSerialization.data(withJSONObject: errorDict)
        } catch {
            logger.error("Failed to serialize error response: \(error)")
            return createErrorResponseSync(originalMessage: message, error: "Failed to serialize error response")
        }

        // 6. Create response payload (matching Rust pattern)
        let responsePayload = NetworkMessagePayloadItem(
            path: message.payload.path,
            payloadBytes: responseBytes,
            correlationId: message.payload.correlationId,
            networkPublicKey: message.payload.networkPublicKey,
            profilePublicKeys: profilePublicKeys
        )

        return NetworkMessage(
            sourceNodeId: nodeId,
            destinationNodeId: message.sourceNodeId,
            messageType: 5, // MESSAGE_TYPE_RESPONSE
            payload: responsePayload
        )
    }

    /// Create error response synchronously
    private nonisolated func createErrorResponseSync(originalMessage: NetworkMessage, error: String) -> NetworkMessage {
        // Create proper error response using AnyValue (matching Rust pattern)
        let errorValue = AnyValue.map([
            "error": AnyValue.primitive(true),
            "message": AnyValue.primitive(error)
        ])
        
        // Serialize with context (matching Rust pattern)
        // Note: This is a synchronous method, so we need to handle async serialization
        let errorBytes: Data
        do {
            // TODO: Implement proper async/sync bridging for serialization
            // For now, create a simple fallback
            let errorDict: [String: Any] = [
                "error": true,
                "message": error
            ]
            errorBytes = try JSONSerialization.data(withJSONObject: errorDict)
        } catch {
            // Fallback to simple string if serialization fails
            errorBytes = Data("{\"error\": true, \"message\": \"\(error)\"}".utf8)
        }
        
        let errorPayload = NetworkMessagePayloadItem(
            path: originalMessage.payload.path,
            payloadBytes: errorBytes,
            correlationId: originalMessage.payload.correlationId,
            networkPublicKey: originalMessage.payload.networkPublicKey,
            profilePublicKeys: originalMessage.payload.profilePublicKeys
        )

        return NetworkMessage(
            sourceNodeId: nodeId,
            destinationNodeId: originalMessage.sourceNodeId,
            messageType: 5, // MESSAGE_TYPE_RESPONSE
            payload: errorPayload
        )
    }

    /// Handle network request asynchronously (wrapper for callback)
    private func handleNetworkRequestAsync(_ message: NetworkMessage) async -> NetworkMessage {
        do {
            return try await handleNetworkRequest(message)
        } catch {
            logger.error("Failed to handle network request: \(error)")
            do {
                return try await createErrorResponse(originalMessage: message, error: error)
            } catch {
                // Fallback to simple error response if serialization fails
                logger.error("Failed to create error response: \(error)")
                return NetworkMessage(
                    sourceNodeId: nodeId,
                    destinationNodeId: message.sourceNodeId,
                    messageType: 5, // MESSAGE_TYPE_RESPONSE
                    payload: NetworkMessagePayloadItem(
                        path: message.payload.path,
                        payloadBytes: Data("{\"error\": true, \"message\": \"Internal error\"}".utf8),
                        correlationId: message.payload.correlationId,
                        networkPublicKey: message.payload.networkPublicKey,
                        profilePublicKeys: message.payload.profilePublicKeys
                    )
                )
            }
        }
    }

    /// Handle network request (async implementation matching Rust)
    private func handleNetworkRequest(_ message: NetworkMessage) async throws -> NetworkMessage {
        logger.trace("[handle_network_request] path: \(message.payload.path) correlation_id: \(message.payload.correlationId) profile_public_keys size: \(message.payload.profilePublicKeys.count)")

        // Deserialize the incoming payload
        let payload = try AnyValue.deserialize(
            message.payload.payloadBytes,
            keystore: keysManager
        )

        let paramsOption: AnyValue? = payload.isNull ? nil : payload

        // Parse topic path to get network ID
        let topicPath = try TopicPath.parse(message.payload.path)
        let networkId = topicPath.networkId
        let profilePublicKeys = message.payload.profilePublicKeys

        // Get network public key from key manager
        // TODO: Implement getNetworkPublicKeyById in FFI - this is missing
        let networkPublicKey = Data() // Placeholder until FFI method is implemented

        // Make the local request
        let response = try await serviceRegistry.request(
            topicPath.asString(),
            payload: paramsOption,
            networkId: networkId
        )

        logger.trace("[handle_network_request] local request completed successfully correlation_id: \(message.payload.correlationId)")

        // Create resolver for response serialization
        let resolver = try getOrCreateResolver(profilePublicKeys)

        // Create serialization context
        let serializationContext = SerializationContext(
            keystore: keysManager,
            resolver: resolver,
            networkId: networkId,
            profilePublicKey: profilePublicKeys.first ?? Data()
        )

        // Serialize the response data
        let serializedData = try await response.serialize(context: serializationContext)

        // Create response NetworkMessage
        return NetworkMessage(
            sourceNodeId: nodeId,
            destinationNodeId: message.sourceNodeId,
            messageType: 5, // MESSAGE_TYPE_RESPONSE
            payload: NetworkMessagePayloadItem(
                path: message.payload.path,
                payloadBytes: serializedData,
                correlationId: message.payload.correlationId,
                networkPublicKey: networkPublicKey,
                profilePublicKeys: profilePublicKeys
            )
        )
    }

    /// Create error response for network request failures
    private func createErrorResponse(originalMessage: NetworkMessage, error: Error) async throws -> NetworkMessage {
        logger.error("❌ [handle_network_request] Local request failed correlation_id: \(originalMessage.payload.correlationId) - Error: \(error)")

        let topicPath = try TopicPath.parse(originalMessage.payload.path)
        let networkId = topicPath.networkId
        let profilePublicKeys = originalMessage.payload.profilePublicKeys

        // Get network public key
        // TODO: Implement getNetworkPublicKeyById in FFI - this is missing
        let networkPublicKey = Data() // Placeholder until FFI method is implemented

        // Create resolver for error response serialization
        let resolver = try getOrCreateResolver(profilePublicKeys)

        // Create serialization context
        let serializationContext = SerializationContext(
            keystore: keysManager,
            resolver: resolver,
            networkId: networkId,
            profilePublicKey: profilePublicKeys.first ?? Data()
        )

        // Create error map
        var errorMap: [String: AnyValue] = [:]
        errorMap["error"] = AnyValue.primitive(true)
        errorMap["message"] = AnyValue.primitive(error.localizedDescription)
        let errorValue = AnyValue.map(errorMap)

        // Serialize the error value
        let serializedError = try await errorValue.serialize(context: serializationContext)

        // Create error response NetworkMessage
        return NetworkMessage(
            sourceNodeId: nodeId,
            destinationNodeId: originalMessage.sourceNodeId,
            messageType: 5, // MESSAGE_TYPE_RESPONSE
            payload: NetworkMessagePayloadItem(
                path: originalMessage.payload.path,
                payloadBytes: serializedError,
                correlationId: originalMessage.payload.correlationId,
                networkPublicKey: networkPublicKey,
                profilePublicKeys: profilePublicKeys
            )
        )
    }

    /// Handle peer connected event
    private func handlePeerConnected(peerNodeId: String, nodeInfo: NodeInfo) async {
        print("🔍 HANDSHAKE: handlePeerConnected called for peer: \(peerNodeId)")
        logger.trace("Peer connected: \(peerNodeId)")
        logger.trace("Peer NodeInfo: \(nodeInfo)")

        // Store peer info in remote_node_info (matching Rust implementation)
        print("🔍 HANDSHAKE: Storing peer info in remote_node_info")
        _ = await remoteNodeInfo.insert(nodeInfo, for: peerNodeId)
        print("🔍 HANDSHAKE: Peer info stored successfully")

        // Process service metadata from the peer's NodeInfo
        let nodeMetadata = nodeInfo.nodeMetadata
        print("🔍 HANDSHAKE: Processing peer service metadata: \(nodeMetadata.services.count) services")
        logger.trace("Processing peer service metadata: \(nodeMetadata.services.count) services")

        // Register remote services from the peer's metadata
        for servicePath in nodeMetadata.services {
            print("🔍 HANDSHAKE: Registering remote service: \(servicePath) from peer: \(peerNodeId)")
            logger.trace("Registering remote service: \(servicePath) from peer: \(peerNodeId)")

            // For now, we'll create a simple remote handler that routes to the peer
            // In a full implementation, we would need to get the actual service metadata
            // from the peer's NodeInfo to know what actions are available
            let remoteHandler: ActionHandler = { [weak self] params, context in
                return try await self?.handleRemoteServiceCall(
                    actionPath: servicePath,
                    peerNodeId: peerNodeId,
                    params: params,
                    context: context
                ) ?? AnyValue.null()
            }

            // Register the remote service handler
            do {
                let topicPath = try TopicPath.parse(servicePath)
                try await serviceRegistry.registerRemoteActionHandler(
                    topicPath: topicPath,
                    handler: remoteHandler
                )
                print("🔍 HANDSHAKE: Successfully registered remote service handler for: \(servicePath)")
            } catch {
                print("🔍 HANDSHAKE: Failed to register remote service handler for \(servicePath): \(error)")
                logger.error("Failed to register remote service handler for \(servicePath): \(error)")
            }
        }
        print("🔍 HANDSHAKE: handlePeerConnected completed for peer: \(peerNodeId)")
    }

    /// Handle remote service call
    private func handleRemoteServiceCall(
        actionPath: String,
        peerNodeId: String,
        params: AnyValue?,
        context: RequestContext
    ) async throws -> AnyValue {
        logger.trace("Handling remote service call: \(actionPath) to peer: \(peerNodeId)")

        // Verify the peer exists
        guard await remoteNodeInfo.contains(peerNodeId) else {
            logger.warning("No NodeInfo found for peer: \(peerNodeId)")
            throw NodeError.peerNotFound("Peer not found: \(peerNodeId)")
        }

        // Use the action path directly since it's already in the correct format
        let fullServicePath = actionPath

        logger.trace("Making remote call to: \(fullServicePath)")

        // Make the remote call using the network transport
        let result = try await request(
            fullServicePath,
            payload: params,
            networkId: context.networkId
        )

        return result
    }

    /// Handle peer disconnected event
    private func handlePeerDisconnected(peerNodeId: String) async {
        logger.trace("Peer disconnected: \(peerNodeId)")

        // Remove peer info from remote_node_info
        _ = await remoteNodeInfo.remove(peerNodeId)

        // TODO: Clean up remote services for this peer
        // This should match the Rust cleanup_disconnected_peer implementation
        // - Remove remote service handlers for this peer
        // - Handle discovery events
    }

    // MARK: - Discovery Event Handlers

    /// Handle peer discovered event from discovery system
    private func handlePeerDiscovered(peerInfo: SwiftFFI.PeerInfo) async {
        logger.trace("🔍 DISCOVERY: Peer discovered: \(peerInfo.addresses)")
        print("🔍 DISCOVERY: Peer discovered with addresses: \(peerInfo.addresses)")

        // Convert SwiftFFI.PeerInfo to a format we can use
        // For now, we'll use the first address as the peer ID
        guard let firstAddress = peerInfo.addresses.first else {
            logger.warning("🔍 DISCOVERY: Peer discovered but no addresses available")
            return
        }

        // Extract peer ID from address or use address as ID
        let peerNodeId = firstAddress

        // Store peer info for later connection
        logger.trace("🔍 DISCOVERY: Storing peer info for \(peerNodeId)")
        
        // Publish discovery event that tests can subscribe to
        // This matches the Rust test expectation: $registry/peer/{nodeId}/discovered
        let discoveryEventPath = "$registry/peer/\(peerNodeId)/discovered"
        logger.trace("🔍 DISCOVERY: Publishing discovery event: \(discoveryEventPath)")
        
        // Publish the discovery event
        do {
            try await publish(
                topic: discoveryEventPath,
                data: AnyValue.primitive(peerNodeId),
                options: PublishOptions()
            )
            logger.trace("🔍 DISCOVERY: Discovery event published successfully")
        } catch {
            logger.error("🔍 DISCOVERY: Failed to publish discovery event: \(error)")
        }
        
        // TODO: Establish connection and perform handshake to get full NodeInfo
        // This would typically trigger a connection attempt to the discovered peer
        // and then register remote service handlers in the service registry
        logger.trace("🔍 DISCOVERY: Peer discovery completed for \(peerNodeId)")
    }

    /// Handle peer updated event from discovery system
    private func handlePeerUpdated(peerInfo: SwiftFFI.PeerInfo) async {
        logger.trace("🔍 DISCOVERY: Peer updated: \(peerInfo.addresses)")
        print("🔍 DISCOVERY: Peer updated with addresses: \(peerInfo.addresses)")

        // Handle peer information updates
        // This could include address changes, service updates, etc.
        guard let firstAddress = peerInfo.addresses.first else {
            logger.warning("🔍 DISCOVERY: Peer updated but no addresses available")
            return
        }

        let peerNodeId = firstAddress
        logger.trace("🔍 DISCOVERY: Peer update completed for \(peerNodeId)")
    }

    /// Handle peer lost event from discovery system
    private func handlePeerLost(nodeId: String) async {
        logger.trace("🔍 DISCOVERY: Peer lost: \(nodeId)")
        print("🔍 DISCOVERY: Peer lost: \(nodeId)")

        // Handle peer being lost from discovery
        // This doesn't necessarily mean the peer disconnected (it might still be connected)
        // but it's no longer discoverable via the discovery mechanism
        
        // TODO: Handle peer lost logic
        // - Mark peer as no longer discoverable
        // - Potentially trigger reconnection attempts
        // - Clean up discovery-specific state
        
        logger.trace("🔍 DISCOVERY: Peer lost handling completed for \(nodeId)")
    }

    /// Handle incoming network request
    private func handleNetworkRequest(
        requestId _: String,
        path: String,
        payload _: Data,
        sourcePeerId _: String,
        correlationId: String?
    ) async -> Data {
        logger.trace("Handling network request: path=\(path), correlationId=\(correlationId ?? "nil")")

        do {
            // Parse the topic path
            let topicPath = try TopicPath.parse(path)
            let networkId = topicPath.networkId

            // TODO: Implement proper payload deserialization from network data
            // For now, create a null value - this needs to be implemented with proper CBOR deserialization
            let deserializedPayload = AnyValue.null()

            let paramsOption = deserializedPayload.isNull ? nil : deserializedPayload

            // Create request context (currently unused due to sync callback limitation)
            let _ = RequestContext(
                topicPath: topicPath,
                networkId: networkId,
                metadata: [:],
                logger: logger,
                pathParams: [:],
                nodeDelegate: self
            )

            // Process the local request (currently unused due to sync callback limitation)
            let _ = try await serviceRegistry.request(
                path,
                payload: paramsOption,
                networkId: networkId
            )

            // TODO: Implement proper response serialization for network transport
            // For now, return empty data - this needs to be implemented with proper CBOR serialization
            let serializedResponse = Data()

            logger.trace("Network request completed successfully: correlationId=\(correlationId ?? "nil")")
            return serializedResponse

        } catch {
            logger.error("Network request failed: \(error)")

            // Create error response (currently unused due to sync callback limitation)
            let _ = AnyValue.map([
                "error": AnyValue.primitive(true),
                "message": AnyValue.primitive(error.localizedDescription),
            ])

            // TODO: Implement proper error response serialization
            // For now, return empty data - this needs to be implemented with proper CBOR serialization
            return Data()
        }
    }

    /// Handle incoming network event
    private func handleNetworkEvent(
        requestId _: String,
        path: String,
        payload _: Data,
        sourcePeerId _: String,
        correlationId: String?
    ) async {
        logger.trace("Handling network event: path=\(path), correlationId=\(correlationId ?? "nil")")

        do {
            // Parse the topic path
            let topicPath = try TopicPath.parse(path)

            // TODO: Implement proper payload deserialization from network data
            // For now, create a null value - this needs to be implemented with proper CBOR deserialization
            let deserializedPayload = AnyValue.null()

            let payloadOption = deserializedPayload.isNull ? nil : deserializedPayload

            // Create event context (currently unused since EventHandler doesn't take context)
            _ = EventContext(
                topicPath: topicPath,
                logger: logger,
                nodeDelegate: self,
                deliveryOptions: nil,
                isLocal: false
            )

            // Get subscribers for this topic
            let subscribers = await serviceRegistry.getLocalEventSubscribers(topicPath: topicPath)

            if subscribers.isEmpty {
                logger.trace("No subscribers found for topic: \(topicPath.rawPath)")
                return
            }

            // Dispatch to all subscribers
            for (_, handler, _) in subscribers {
                await handler(payloadOption)
            }

            logger.trace("Network event dispatched successfully")

        } catch {
            logger.error("Network event handling failed: \(error)")
        }
    }
}

// MARK: - QuicTransport NodeTransport Conformance

@MainActor
extension QuicTransport: NodeTransport {
    public func sendRequest(path: String, payload: Data, correlationId: String) async throws {
        // Create TransportRequestParams for the request
        let requestParams = TransportRequestParams(
            path: path,
            correlationId: correlationId,
            payload: payload,
            destPeerId: "" // Will be determined by the transport layer
        )

        // Send the request (response will be handled by callbacks)
        _ = try await request(requestParams)
    }

    public func completeRequest(requestId: String, responsePayload: Data, profilePublicKey: Data?) async throws {
        // Create TransportCompleteRequestParams for the response
        let completeParams = TransportCompleteRequestParams(
            requestId: requestId,
            responsePayload: responsePayload,
            profilePublicKeys: profilePublicKey != nil ? [profilePublicKey!] : []
        )

        // Complete the request using the QuicTransport method
        try await completeRequest(completeParams)
    }

    public func publish(topic: String, payload: Data, options _: PublishOptions) async throws {
        // Create TransportPublishParams for the event
        let publishParams = TransportPublishParams(
            path: topic,
            correlationId: UUID().uuidString,
            payload: payload,
            destPeerId: "" // PublishOptions doesn't have destinationPeerId, use empty string
        )

        // Publish the event
        try await publish(publishParams)
    }

    public func subscribe(topic _: String, subscriptionId _: String) async throws {
        // TODO: Implement event subscription
        // This would require implementing subscription management in the transport layer
        throw NodeError.transportNotImplemented("Event subscription not implemented")
    }

    public func unsubscribe(subscriptionId _: String) async throws {
        // TODO: Implement event unsubscription
        // This would require implementing subscription management in the transport layer
        throw NodeError.transportNotImplemented("Event unsubscription not implemented")
    }


    public func localAddr() async throws -> String {
        // Use the existing getLocalAddr method
        try await getLocalAddr()
    }

    public func updateLocalNodeInfo(_ nodeInfo: Data) async throws {
        // Decode the CBOR data to SwiftFFI.NodeInfo and update
        let ffiNodeInfo = try CodableCBORDecoder().decode(SwiftFFI.NodeInfo.self, from: nodeInfo)
        try await updateLocalNodeInfo(nodeInfo: ffiNodeInfo)
    }
}

// MARK: - NodeDelegate Implementation

extension Node: NodeDelegate {
    public func registerAction(networkId: String, servicePath: String, action: String, handler: @escaping ActionHandler) async throws {
        try await serviceRegistry.registerAction(networkId: networkId, servicePath: servicePath, action: action, handler: handler)
    }

    public func unregisterAction(networkId: String, servicePath: String, action: String) async throws {
        try await serviceRegistry.unregisterAction(networkId: networkId, servicePath: servicePath, action: action)
    }

    public func subscribeToEvents(networkId: String, servicePath: String, handler: @escaping EventHandler) async throws -> String {
        try await serviceRegistry.subscribeToEvents(networkId: networkId, servicePath: servicePath, handler: handler)
    }

    public func unsubscribeFromEvents(subscriptionId: String) async throws {
        await serviceRegistry.unsubscribeFromEvents(subscriptionId: subscriptionId)
    }

    public func publish(topic: String, data: AnyValue?) async throws {
        try await publish(topic: topic, data: data, options: nil)
    }
}

// MARK: - RegistryDelegate Implementation

extension Node: RegistryDelegate {
    public func getLocalServiceState(servicePath: TopicPath) async -> ServiceState? {
        await serviceRegistry.getLocalServiceState(servicePath: servicePath)
    }

    public func getRemoteServiceState(servicePath _: TopicPath) async -> ServiceState? {
        // TODO: Implement remote service state lookup when networking is available
        nil
    }

    public func getServiceMetadata(servicePath: TopicPath) async -> ServiceMetadata? {
        await serviceRegistry.getServiceMetadata(servicePath: servicePath)
    }

    public func getAllServiceMetadata(includeInternalServices: Bool) async throws -> [String: ServiceMetadata] {
        await serviceRegistry.getAllLocalServiceMetadata(includeInternalServices: includeInternalServices)
    }

    public func getActionsMetadata(serviceTopicPath _: TopicPath) async -> [ActionMetadata] {
        // TODO: Implement actions metadata lookup
        []
    }

    public func registerRemoteActionHandler(topicPath _: TopicPath, handler _: ActionHandler) async throws {
        // TODO: Implement remote action handler registration when networking is available
    }

    public func removeRemoteActionHandler(topicPath _: TopicPath) async throws {
        // TODO: Implement remote action handler removal when networking is available
    }

    public func registerRemoteEventHandler(topicPath _: TopicPath, handler _: EventHandler) async throws {
        // TODO: Implement remote event handler registration when networking is available
    }

    public func removeRemoteEventHandler(topicPath _: TopicPath) async throws {
        // TODO: Implement remote event handler removal when networking is available
    }

    public func updateLocalServiceStateIfValid(servicePath: TopicPath, newState: ServiceState, currentState: ServiceState) async throws {
        try await serviceRegistry.updateLocalServiceStateIfValid(servicePath: servicePath, newState: newState, currentState: currentState)
    }

    public func validatePauseTransition(servicePath: TopicPath) async throws {
        try await serviceRegistry.validatePauseTransition(servicePath: servicePath)
    }

    public func validateResumeTransition(servicePath: TopicPath) async throws {
        try await serviceRegistry.validateResumeTransition(servicePath: servicePath)
    }
}

// MARK: - Node Errors

/// Errors that can occur during node operations
public enum NodeError: Error, Sendable {
    case missingKeyManager(String)
    case missingNodePublicKey(String)
    case serviceRegistrationFailed(String)
    case networkInitializationFailed(String)
    case invalidConfiguration(String)
    case transportNotImplemented(String)
    case discoveryNotImplemented(String)
    case invalidServicePath(String)
    case serviceInitializationFailed(String)
    case peerNotFound(String)
    case invalidPath(String)
    case serviceNotFound(String)

    public var localizedDescription: String {
        switch self {
        case let .missingKeyManager(message):
            "Missing key manager: \(message)"
        case let .missingNodePublicKey(message):
            "Missing node public key: \(message)"
        case let .serviceRegistrationFailed(message):
            "Service registration failed: \(message)"
        case let .networkInitializationFailed(message):
            "Network initialization failed: \(message)"
        case let .invalidConfiguration(message):
            "Invalid configuration: \(message)"
        case let .invalidServicePath(message):
            "Invalid service path: \(message)"
        case let .serviceInitializationFailed(message):
            "Service initialization failed: \(message)"
        case let .transportNotImplemented(message):
            "Transport not implemented: \(message)"
        case let .discoveryNotImplemented(message):
            "Discovery not implemented: \(message)"
        case let .peerNotFound(message):
            "Peer not found: \(message)"
        case let .invalidPath(message):
            "Invalid path: \(message)"
        case let .serviceNotFound(message):
            "Service not found: \(message)"
        }
    }
}
