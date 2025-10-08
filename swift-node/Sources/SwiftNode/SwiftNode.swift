import Foundation
import RunarSerializer
import SwiftCBOR
import SwiftCommon
import SwiftFFI

// MARK: - Type Aliases for SwiftFFI Types

/// Use SwiftFFI types directly - no duplication
public typealias ActionMetadata = SwiftFFI.ActionMetadata
public typealias ServiceMetadata = SwiftFFI.ServiceMetadata
public typealias FieldSchema = SwiftFFI.FieldSchema
public typealias SchemaDataType = SwiftFFI.SchemaDataType

// MARK: - FFI Integration

/// Type alias for FFIKeys to use real NodeKeyManager from swift-ffi
public typealias FFIKeys = NodeKeyManager

// MARK: - Missing Types and Protocols

/// Protocol for network transport implementations
public protocol NodeTransport: AnyObject, Sendable {
    func start() async throws
    func stop() async throws
    func connectToPeer(peerInfo: SwiftFFI.PeerInfo) async throws
    func sendRequest(path: String, payload: Data, correlationId: String) async throws
    func completeRequest(requestId: String, responsePayload: Data, profilePublicKey: Data?) async throws
    func publish(topic: String, payload: Data, options: PublishOptions) async throws
    func subscribe(topic: String, subscriptionId: String) async throws
    func unsubscribe(subscriptionId: String) async throws
    func localAddr() async throws -> String
    func updateLocalNodeInfo(nodeInfo: SwiftFFI.NodeInfo) async throws
    func request(path: String, correlationId: String, payload: Data, peerNodeId: String, networkPublicKey: Data?, profilePublicKeys: [Data]) async throws -> Data
}

/// Protocol for load balancing strategies
public protocol LoadBalancingStrategy: Sendable {
    func selectHandler(handlers: [some Sendable], context: RequestContext?) async -> Int?
}

/// Round-robin load balancer implementation (actor-based)
public actor RoundRobinLoadBalancer: LoadBalancingStrategy {
    private var currentIndex: Int = 0

    public init() {}

    public func selectHandler(handlers: [some Sendable], context _: RequestContext?) async -> Int? {
        guard !handlers.isEmpty else { return nil }
        let selectedIndex = currentIndex % handlers.count
        currentIndex &+= 1
        return selectedIndex
    }
}

// Discovery classes moved to swift-ffi package

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
    public let path: String = "$registry"
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

            logger.debug("RegistryService.services/list: Listing all services")

            // Extract parameters from the request (matching Rust implementation)
            let includeInternalServices: Bool
            let includeRemoteServices: Bool

            if let paramsMap = try await payload?.asType() as [String: AnyValue]? {
                includeInternalServices = try await paramsMap["include_internal_services"]?.asType() as Bool? ?? true
                includeRemoteServices = try await paramsMap["include_remote_services"]?.asType() as Bool? ?? true
            } else {
                // Default to true if params is not a map (matching Rust)
                includeInternalServices = true
                includeRemoteServices = true
            }

            logger.debug("RegistryService.services/list: include_internal_services=\(includeInternalServices), include_remote_services=\(includeRemoteServices)")

            // Get all service metadata with the specified flags (matching Rust)
            let allMetadata = try await registryDelegate.getAllServiceMetadata(
                includeInternalServices: includeInternalServices,
                includeRemoteServices: includeRemoteServices
            )

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
            let servicePath = try TopicPath.new(servicePathString, defaultNetwork: requestContext.networkId)

            // Get service metadata
            if let metadata = try await registryDelegate.getServiceMetadata(servicePath: servicePath) {
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
            let servicePath = try TopicPath.new(servicePathString, defaultNetwork: requestContext.networkId)

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
            let servicePath = try TopicPath.new(servicePathString, defaultNetwork: requestContext.networkId)

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
            let servicePath = try TopicPath.new(servicePathString, defaultNetwork: requestContext.networkId)

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
    public let path: String = "$keys"
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
    public var config: AnyValue?
    /// Logger instance with service context
    public let logger: RunarLogger
    /// Node delegate for node operations
    public let nodeDelegate: NodeDelegate

    /// Create a new LifecycleContext with a topic path and logger (matching Rust exactly)
    public init(
        topicPath: TopicPath,
        nodeDelegate: NodeDelegate,
        logger: RunarLogger
    ) {
        networkId = topicPath.networkId
        servicePath = topicPath.servicePath
        config = nil
        self.logger = logger
        self.nodeDelegate = nodeDelegate
    }

    /// Add configuration to a LifecycleContext (matching Rust builder pattern)
    public func withConfig(_ config: AnyValue) -> LifecycleContext {
        var newContext = self
        newContext.config = config
        return newContext
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
    /// Metadata for this request
    public let metadata: [String: AnyValue]
    /// Logger for this context
    public let logger: RunarLogger
    /// Path parameters extracted from template matching
    public var pathParams: [String: String]
    /// Node delegate for making requests or publishing events
    public let nodeDelegate: NodeDelegate

    /// Create a new RequestContext with a TopicPath and logger (matching Rust exactly)
    public init(
        topicPath: TopicPath,
        nodeDelegate: NodeDelegate,
        metadata: [String: AnyValue],
        logger: RunarLogger
    ) {
        self.topicPath = topicPath
        self.metadata = metadata
        self.logger = logger
        pathParams = [:]
        self.nodeDelegate = nodeDelegate
    }

    /// Get the network ID from the topic path (matching Rust network_id method)
    public var networkId: String {
        topicPath.networkId
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
    func getServiceMetadata(servicePath: TopicPath) async throws -> ServiceMetadata?
    func getAllServiceMetadata(includeInternalServices: Bool, includeRemoteServices: Bool) async throws -> [String: ServiceMetadata]
    func getActionsMetadata(serviceTopicPath: TopicPath) async throws -> [ActionMetadata]
    func registerRemoteActionHandler(topicPath: TopicPath, handler: @escaping ActionHandler) async throws
    func removeRemoteActionHandler(topicPath: TopicPath) async throws
    func registerRemoteEventHandler(topicPath: TopicPath, handler: @escaping EventHandler) async throws
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
/// Matches Rust: EventHandler = Arc<dyn Fn(Arc<EventContext>, Option<ArcValue>) -> Pin<Box<dyn Future<Output = Result<()>> + Send>> + Send + Sync>
public typealias EventHandler = @Sendable (EventContext, AnyValue?) async throws -> Void

/// Remote event handler type
/// Matches Rust: RemoteEventHandler = Arc<dyn Fn(Option<ArcValue>) -> Pin<Box<dyn Future<Output = Result<()>> + Send>> + Send + Sync>
public typealias RemoteEventHandler = @Sendable (AnyValue?) async throws -> Void

/// Publish options
public struct PublishOptions: Sendable {
    public var broadcast: Bool
    public var guaranteedDelivery: Bool
    public var retainFor: TimeInterval?
    public var profilePublicKeys: [Data]?
    public var target: String?

    public init(
        broadcast: Bool = false,
        guaranteedDelivery: Bool = false,
        retainFor: TimeInterval? = nil,
        profilePublicKeys: [Data]? = nil,
        target: String? = nil
    ) {
        self.broadcast = broadcast
        self.guaranteedDelivery = guaranteedDelivery
        self.retainFor = retainFor
        self.profilePublicKeys = profilePublicKeys
        self.target = target
    }

    /// Create local-only publish options (matching Rust PublishOptions::local_only())
    public static func localOnly() -> PublishOptions {
        PublishOptions(
            broadcast: false,
            guaranteedDelivery: false,
            retainFor: nil,
            profilePublicKeys: nil,
            target: nil
        )
    }

    /// Add retention duration (matching Rust with_retain_for pattern)
    public func withRetainFor(_ duration: TimeInterval) -> PublishOptions {
        var newOptions = self
        newOptions.retainFor = duration
        return newOptions
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

/// Request options matching Rust RequestOptions
public struct RequestOptions: Sendable {
    public let profilePublicKeys: [[UInt8]]?

    public init(profilePublicKeys: [[UInt8]]? = nil) {
        self.profilePublicKeys = profilePublicKeys
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
    public var loggerConfig: LoggerConfig?

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
        loggerConfig = LoggerConfigManager.shared.globalConfig
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
        newConfig.loggerConfig = config
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

// NodeInfo and NodeMetadata are now type aliases to SwiftFFI types
public typealias NodeInfo = SwiftFFI.NodeInfo
public typealias NodeMetadata = SwiftFFI.NodeMetadata
public typealias SubscriptionMetadata = SwiftFFI.SubscriptionMetadata

// MARK: - Service Task

/// Service task type alias matching Rust exactly: (TopicPath, Task<Void, Never>)
public typealias ServiceTask = (TopicPath, Task<Void, Never>)

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

// MARK: - Node Public API Extensions

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
    private var networkDiscoveryProviders: [SwiftFFI.NodeDiscovery]?

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

    /// Service tasks for tracking service lifecycle (matching Rust service_tasks exactly)
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
        // Clone fields before moving config
        let defaultNetworkId = config.defaultNetworkId
        let networkingEnabled = config.networkConfig != nil

        var networkIds = config.networkIds
        networkIds.append(defaultNetworkId)
        networkIds = Array(Set(networkIds)) // Remove duplicates

        let logger = RunarLogger.root(component: .node, config: config.loggerConfig)
        let serviceRegistry = ServiceRegistry(logger: logger) // Will be set after initialization

        // Extract the key manager from config
        guard let keysManager = config.getKeyManager() else {
            throw NodeError.missingKeyManager("Failed to load node credentials.")
        }

        let nodePublicKey = try await keysManager.getNodePublicKey()

        let nodeId = try await keysManager.getCompactId(for: nodePublicKey)
        logger.setContext(nodeId)

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
    private func getOrCreateResolver(userProfileKeys: [Data]) async throws -> LabelResolver {
        try await labelResolverCache.getOrCreateResolver(
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
        let topicPath = try TopicPath.new(topic, defaultNetwork: networkId)

        // Notify local subscribers first (Registry manages subscriptions, Node invokes handlers)
        logger.debug("Publishing event to topic: \(topic) with data: \(String(describing: data))")
        let localSubscribers = await serviceRegistry.getLocalEventSubscribers(topicPath: topicPath)
        for (subscriptionId, handler, _) in localSubscribers {
            logger.trace("Invoking local subscription handler id=\(subscriptionId) for topic: \(topicPath.asString())")
            let eventContext = EventContext(
                topicPath: topicPath,
                nodeDelegate: self,
                isLocal: true,
                logger: logger
            )
            do {
                try await handler(eventContext, data)
            } catch {
                logger.error("Error in local event handler for \(topic): \(error)")
            }
        }

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
            let remoteSubscribers = await serviceRegistry.getRemoteEventSubscribers(topicPath: topicPath)
            for (subscriptionId, remoteHandler, _) in remoteSubscribers {
                logger.trace("Invoking remote subscription handler id=\(subscriptionId) for topic: \(topicPath.asString())")
                do {
                    try await remoteHandler(data)
                } catch {
                    logger.error("Error in remote event handler for \(topic): \(error)")
                }
            }
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
        let topicPath = try TopicPath.new(topic, defaultNetwork: networkId)

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
                // Create event context for the callback
                let eventContext = EventContext(
                    topicPath: topicPath,
                    nodeDelegate: self,
                    isLocal: true,
                    logger: logger
                )
                try await callback(eventContext, data)
            } else {
                logger.debug("No retained event found for topic '\(topic)' within lookback window")
            }
        }

        return subscriptionId
    }

    /// Subscribe to events on a topic with timeout (matching Rust `on` method)
    ///
    /// INTENTION: Subscribe to events with a timeout, matching the Rust `on` method pattern.
    /// This is used for waiting for specific events like peer discovery.
    ///
    /// - Parameters:
    ///   - topic: The topic path to subscribe to (e.g., "$registry/peer/{nodeId}/discovered")
    ///   - options: Event registration options including timeout
    ///   - callback: The callback to invoke when events are received
    /// - Returns: A subscription ID that can be used to unsubscribe
    ///
    /// Example:
    /// ```swift
    /// let subscriptionId = try await node.on("$registry/peer/\(peerId)/discovered",
    ///     options: EventRegistrationOptions(timeout: 3.0)) { data in
    ///     print("Peer discovered: \(data)")
    /// }
    /// ```
    public func on(topic: String, options: EventRegistrationOptions? = nil, callback: @escaping EventHandler) async throws -> String {
        try await subscribe(topic: topic, options: options, callback: callback)
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
        // Check if service already has a network ID, otherwise use default (matching Rust exactly)
        let serviceNetworkId = service.networkId ?? networkId
        service.setNetworkId(serviceNetworkId)

        let servicePath = service.path
        let serviceName = service.name

        logger.trace("Adding service '\(serviceName)' to node using path \(servicePath)")
        logger.debug("network id \(networkId)")

        // Create a proper topic path for the service (matching Rust pattern exactly)
        let serviceTopic: TopicPath
        do {
            serviceTopic = try TopicPath.new(servicePath, defaultNetwork: networkId)
        } catch {
            logger.error("Failed to create topic path for service name:\(serviceName) path:\(servicePath) error:\(error)")
            throw NodeError.invalidConfiguration("Failed to create topic path for service \(serviceName): \(error)")
        }

        // Create a lifecycle context for initialization (matching Rust pattern exactly)
        let initContext = LifecycleContext(
            topicPath: serviceTopic,
            nodeDelegate: self,
            logger: logger
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
            // Publish error event (matching Rust pattern exactly)
            try await publish(
                topic: "$registry/services/\(servicePath)/state/error",
                data: AnyValue.primitive(serviceTopic.rawPath),
                options: PublishOptions(
                    broadcast: false,
                    guaranteedDelivery: false,
                    retainFor: 10.0,
                    profilePublicKeys: nil,
                    target: nil
                )
            )
            throw NodeError.serviceInitializationFailed("Failed to initialize service: \(error)")
        }

        // Update service state to initialized (matching Rust pattern)
        try await serviceRegistry.updateLocalServiceState(
            servicePath: serviceTopic.rawPath,
            newState: ServiceState.initialized
        )

        // Publish initialized event (matching Rust pattern exactly)
        try await publish(
            topic: "$registry/services/\(servicePath)/state/initialized",
            data: AnyValue.primitive(serviceTopic.rawPath),
            options: PublishOptions(
                broadcast: false,
                guaranteedDelivery: false,
                retainFor: 10.0,
                profilePublicKeys: nil,
                target: nil
            )
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
            logger.trace("🔍 SERVICE: Node is running, updating transport with new NodeInfo...")
            try await updateTransportNodeInfo()
        } else {
            logger.trace("🔍 SERVICE: Node not yet started, transport will be created with current NodeInfo when started")
        }

        // If the node is already running, start the service immediately (matching Rust pattern)
        if isRunning {
            await startService(serviceTopic: serviceTopic, serviceEntry: serviceEntry, updateNodeVersion: true)
        }
    }

    /// Start a specific service (matching Rust start_service exactly)
    private func startService(serviceTopic: TopicPath, serviceEntry: ServiceEntry, updateNodeVersion: Bool = false) async {
        logger.info("[start_service] Starting service: \(serviceTopic)")

        let service = serviceEntry.service
        let registry = serviceRegistry

        // Create a lifecycle context for starting (matching Rust exactly)
        let startContext = LifecycleContext(
            topicPath: serviceTopic,
            nodeDelegate: self, // Node delegate
            logger: logger // Use the node logger directly
        )

        // Start the service using the context (matching Rust exactly)
        do {
            try await service.start(startContext)
        } catch {
            logger.error("[start_service] Failed to start service: \(serviceTopic), error: \(error)")

            // Update service state to Error (matching Rust exactly)
            do {
                try await registry.updateLocalServiceState(
                    servicePath: serviceTopic.rawPath,
                    newState: ServiceState.error
                )
            } catch {
                logger.error("[start_service] Failed to update service state to Error: \(error)")
            }

            // Publish error state (matching Rust exactly)
            do {
                try await publish(
                    topic: "$registry/services/\(serviceTopic.servicePath)/state/error",
                    data: AnyValue.primitive(serviceTopic.rawPath),
                    options: PublishOptions(
                        broadcast: false,
                        guaranteedDelivery: false,
                        retainFor: 10.0,
                        profilePublicKeys: nil,
                        target: nil
                    )
                )
            } catch {
                logger.error("[start_service] Failed to publish error state: \(error)")
            }
            return
        }

        // Update service state to Running (matching Rust exactly)
        do {
            try await registry.updateLocalServiceState(
                servicePath: serviceTopic.rawPath,
                newState: ServiceState.running
            )
        } catch {
            logger.error("[start_service] Failed to update service state to Running: \(error)")
        }

        // Publish running state (matching Rust exactly)
        do {
            try await publish(
                topic: "$registry/services/\(serviceTopic.servicePath)/state/running",
                data: AnyValue.primitive(serviceTopic.rawPath),
                options: PublishOptions(
                    broadcast: false,
                    guaranteedDelivery: false,
                    retainFor: 120.0,
                    profilePublicKeys: nil,
                    target: nil
                )
            )
        } catch {
            logger.error("[start_service] Failed to publish running state: \(error)")
        }

        logger.info("[start_service] published local-only running for local service \(serviceTopic)")

        if updateNodeVersion {
            logger.info("[start_service] notifying node change for service: \(serviceTopic)")
            do {
                try await notifyNodeChange()
            } catch {
                logger.error("Failed to notify node change: \(error)")
            }
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
        logger.info("Starting node...")

        // Check if already running (matching Rust exactly)
        if running {
            logger.warning("Node already running")
            return
        }

        // Get services directly from the registry (matching Rust exactly)
        let localServices = await serviceRegistry.getLocalServices()

        // Separate internal vs non-internal services (matching Rust exactly)
        let internalServices = localServices.filter { _, serviceEntry in
            serviceRegistry.isInternalService(serviceEntry.service.path)
        }
        let nonInternalServices = localServices.filter { _, serviceEntry in
            !serviceRegistry.isInternalService(serviceEntry.service.path)
        }

        // Start internal services first (matching Rust exactly)
        for (serviceTopic, serviceEntry) in internalServices {
            await startService(serviceTopic: serviceTopic, serviceEntry: serviceEntry, updateNodeVersion: false)
        }

        // Start networking if enabled (matching Rust exactly)
        if supportsNetworking {
            do {
                try await startNetworking()
            } catch {
                logger.error("Failed to start networking components: \(error)")
                throw error
            }
        }

        logger.info("Node started successfully - it will start all services now")
        running = true

        // Start non-internal services in parallel to avoid blocking the loop (matching Rust exactly)
        let serviceStartTimeout: TimeInterval = 30.0 // TODO: MOVE THIS TO A CONFIG
        for (serviceTopic, serviceEntry) in nonInternalServices {
            let nodeRef = self
            let serviceTopicRef = serviceTopic
            let serviceEntryRef = serviceEntry

            let task = Task {
                logger.info("Starting separate thread to start service: \(serviceTopicRef)")

                // Add timeout to the service start operation (matching Rust exactly)
                do {
                    try await withTimeout(serviceStartTimeout) {
                        await nodeRef.startService(serviceTopic: serviceTopicRef, serviceEntry: serviceEntryRef, updateNodeVersion: true)
                    }
                    logger.info("Service start completed: \(serviceTopicRef)")
                } catch {
                    logger.error("Service start timed out after 30 seconds: \(serviceTopicRef)")
                }
            }

            // Store the task for later waiting (matching Rust exactly: tasks_store.push((service_topic.clone(), task)))
            serviceTasks.append((serviceTopicRef, task))
        }
    }

    /// Helper function to implement timeout (matching Rust timeout pattern)
    private func withTimeout<T: Sendable>(_ timeout: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw NodeError.timeout("Operation timed out after \(timeout) seconds")
            }

            guard let result = try await group.next() else {
                throw NodeError.timeout("Operation timed out after \(timeout) seconds")
            }

            group.cancelAll()
            return result
        }
    }

    /// Start networking components (matching Rust start_networking)
    private func startNetworking() async throws {
        try await initializeNetworkTransport()

        // Update the transport with current NodeInfo after it's created
        // This ensures the transport has the latest NodeInfo with all services
        logger.trace("🔍 START: Updating transport with current NodeInfo after creation...")
        try await updateTransportNodeInfo()
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
        logger.info("Stopping node...")

        if !running {
            logger.warning("Node already stopped")
            return
        }

        running = false

        // Wait for services to finish any ongoing operations (matching Rust exactly)
        do {
            try await waitForServicesToStart()
        } catch {
            logger.error("Error waiting for services to start: \(error)")
        }

        // Get services directly and stop them (matching Rust exactly)
        let localServices = await serviceRegistry.getLocalServices()

        logger.info("Stopping services...")
        // Stop each service (matching Rust exactly)
        for (serviceTopic, serviceEntry) in localServices {
            logger.info("Stopping service: \(serviceTopic)")

            // Extract the service from the entry
            let service = serviceEntry.service

            // Create a lifecycle context for stopping (matching Rust exactly)
            let stopContext = LifecycleContext(
                topicPath: serviceTopic,
                nodeDelegate: self, // Node delegate
                logger: logger // Use the node logger directly
            )

            // Stop the service using the context (matching Rust exactly)
            do {
                try await service.stop(stopContext)
            } catch {
                logger.error("Failed to stop service: \(serviceTopic), error: \(error)")
                continue
            }

            // Update service state to stopped (matching Rust exactly)
            do {
                try await serviceRegistry.updateLocalServiceState(
                    servicePath: serviceTopic.rawPath,
                    newState: ServiceState.stopped
                )
            } catch {
                logger.error("Failed to update service state to stopped: \(error)")
            }

            // Publish stopped state (matching Rust exactly)
            do {
                try await publish(
                    topic: "$registry/services/\(serviceTopic.servicePath)/state/stopped",
                    data: AnyValue.primitive(serviceTopic.rawPath),
                    options: PublishOptions(
                        broadcast: false,
                        guaranteedDelivery: false,
                        retainFor: 3.0, // Matching Rust: Duration::from_secs(3)
                        profilePublicKeys: nil,
                        target: nil
                    )
                )
            } catch {
                logger.error("Failed to publish stopped state: \(error)")
            }
        }

        // Stop networking if enabled (matching Rust exactly)
        if supportsNetworking {
            do {
                try await shutdownNetwork()
            } catch {
                logger.error("Failed to shutdown network: \(error)")
            }
        }

        // Stop all service tasks (matching Rust exactly)
        for (_, task) in serviceTasks {
            task.cancel() // Swift equivalent of task.abort()
        }
        serviceTasks.removeAll()

        logger.info("Node stopped successfully")
    }

    /// Shutdown the network components (matching Rust shutdown_network exactly)
    private func shutdownNetwork() async throws {
        // Early return if networking is disabled (matching Rust exactly)
        if !supportsNetworking {
            logger.debug("Network shutdown skipped - networking is disabled")
            return
        }

        logger.info("Shutting down network discovery providers")

        // Discovery: collect providers first to avoid holding lock during await (matching Rust exactly)
        let providersToShutdown = networkDiscoveryProviders
        if let discovery = providersToShutdown {
            for provider in discovery {
                try await provider.stop()
            }
        }

        logger.info("Shutting down transport")

        // Transport: clone handle first to avoid holding lock during await (matching Rust exactly)
        let transportToStop = networkTransport
        if let transport = transportToStop {
            try await transport.stop()
        }
    }

    /// Wait for all services to start (matching Rust wait_for_services_to_start exactly)
    public func waitForServicesToStart() async throws {
        logger.trace("Waiting for all services to start...")

        // Wait for all service tasks to complete (matching Rust: for (_service_topic, task) in service_tasks.drain(..))
        for (_, task) in serviceTasks {
            await task.value
        }

        // Clear the tasks after waiting (matching Rust: service_tasks.drain(..))
        serviceTasks.removeAll()

        logger.trace("All services have started successfully")
    }

    /// Debounced notification of node change (matching Rust notify_node_change exactly)
    ///
    /// INTENTION: This function is debounced to avoid flooding the network with repeated notifications.
    /// If called multiple times in rapid succession, only the last call within a 1 second window will
    /// trigger the actual notification. After the debounce period, it delegates to notifyNodeChangeImpl,
    /// which sends the latest node info to all known peers via the transport.
    public func notifyNodeChange() async throws {
        // Check if network is enabled (matching Rust exactly)
        if !supportsNetworking {
            logger.debug("notify_node_change called - network is not available")
            return
        }

        logger.info("notify_node_change called - it will be debounced for 1 second")

        // Cancel any existing debounce task (matching Rust exactly)
        debounceTask?.cancel()

        // Spawn a new debounce task (matching Rust exactly)
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            // Ignore errors from notifyNodeChangeImpl; log if needed
            do {
                try await notifyNodeChangeImpl()
            } catch {
                logger.warning("notify_node_change_impl failed after debounce: \(error)")
            }
        }
    }

    /// Implementation of node change notification (matching Rust notify_node_change_impl exactly)
    private func notifyNodeChangeImpl() async throws {
        // This would typically update the registry version and send node info to peers
        // For now, we'll implement a basic version that matches the Rust structure
        logger.info("Notifying node change - updating node info")

        // Update transport with current node info (matching Rust pattern)
        if networkTransport != nil {
            try await updateTransportNodeInfo()
        }
    }

    /// Make a request to a service
    ///
    /// This method forwards the request to the ServiceRegistry for processing.
    public func request(_ path: String, payload: AnyValue?, options: RequestOptions? = nil) async throws -> AnyValue {
        let actualNetworkId = networkId
        let requestPayload = payload ?? AnyValue.null()

        // Parse topic path (matching Rust pattern exactly)
        let topicPath: TopicPath
        do {
            topicPath = try TopicPath.new(path, defaultNetwork: actualNetworkId)
        } catch {
            throw NodeError.invalidPath("Failed to parse topic path: \(path) : \(error)")
        }

        logger.debug("Processing request: \(topicPath.asString())")

        // 1. Check local service state first (matching Rust pattern exactly)
        let serviceTopic = TopicPath.newService(actualNetworkId, serviceName: topicPath.servicePath)
        let serviceState = await serviceRegistry.getLocalServiceState(servicePath: serviceTopic)

        // 2. If service exists but not running, try remote handlers (matching Rust pattern exactly)
        if let state = serviceState {
            if state != ServiceState.running {
                logger.debug("Service \(topicPath.servicePath) is in \(state) state, trying remote handlers")
                // Try remote handlers instead
                do {
                    let response = try await remoteRequest(path: path, payload: requestPayload, options: options)
                    return response
                } catch {
                    logger.error("Remote request failed: \(error)")
                    // Remote request failed - return state-specific error since we know local service exists but is not running
                    throw NodeError.serviceNotFound("Service is not Running - it is in \(state) state")
                }
            }
        }

        // 3. Check for local handler (matching Rust pattern exactly)
        if let (handler, registrationPath) = await serviceRegistry.getLocalActionHandler(topicPath: topicPath) {
            logger.debug("Executing local handler for: \(topicPath.asString())")

            // Create request context with profile public keys (matching Rust pattern exactly)
            var metadata: [String: AnyValue] = [:]
            metadata["node_id"] = AnyValue.primitive(nodeId)

            // Extract profile public keys from options (matching Rust pattern exactly)
            let profilePublicKeys = options?.profilePublicKeys ?? []
            let profileKeysList: [AnyValue] = profilePublicKeys.map { AnyValue.primitive(Data($0)) }
            metadata["profile_public_keys"] = AnyValue.list(profileKeysList)

            // Extract parameters using the original registration path (matching Rust pattern exactly)
            let pathParams = topicPath.extractParams(registrationPath.actionPath) ?? [:]
            logger.debug("Extracted path parameters: \(pathParams)")

            // Create request context with extracted path parameters (matching Rust exactly)
            var requestContext = RequestContext(
                topicPath: topicPath,
                nodeDelegate: self,
                metadata: metadata,
                logger: logger
            )
            requestContext.pathParams = pathParams

            // Execute the handler and return result
            let response = try await handler(requestPayload, requestContext)
            return response
        }

        // 4. No local handler found - try remote handlers (matching Rust pattern exactly)
        return try await remoteRequest(path: path, payload: requestPayload, options: options)
    }

    /// Local request method (matching Rust local_request exactly)
    /// Only checks for local handlers - no remote fallback to avoid infinite recursion
    private func localRequest(_ path: String, payload: AnyValue?, options: RequestOptions? = nil) async throws -> AnyValue {
        let topicPath = try TopicPath.new(path, defaultNetwork: networkId)

        logger.debug("Processing local request: \(topicPath.asString())")

        // First check for local handlers (matching Rust exactly)
        if let (handler, registrationPath) = await serviceRegistry.getLocalActionHandler(topicPath: topicPath) {
            logger.debug("Executing local handler for: \(topicPath.asString())")

            let profilePublicKeys = options?.profilePublicKeys ?? []
            let profileKeysList: [AnyValue] = profilePublicKeys.map { AnyValue.primitive(Data($0)) }

            var metadata: [String: AnyValue] = [:]
            metadata["node_id"] = AnyValue.primitive(nodeId)
            metadata["profile_public_keys"] = AnyValue.list(profileKeysList)

            // Create request context (matching Rust exactly)
            var requestContext = RequestContext(
                topicPath: topicPath,
                nodeDelegate: self,
                metadata: metadata,
                logger: logger
            )

            // Extract parameters using the original registration path (matching Rust exactly)
            if let pathParams = topicPath.extractParams(registrationPath.actionPath) {
                requestContext.pathParams = pathParams
                logger.debug("Extracted path parameters: \(pathParams)")
            }

            // Execute the handler and return result (matching Rust exactly)
            return try await handler(payload ?? AnyValue.null(), requestContext)
        }

        // No local handler found (matching Rust exactly)
        throw NodeError.serviceNotFound("No local handler found for: \(topicPath.asString())")
    }

    // MARK: - Private Helper Methods

    /// Extract profile public keys from AnyValue (helper for pattern matching)
    private func extractProfilePublicKeys(from value: AnyValue) async throws -> [Data] {
        // Check if it's a list
        if value.category == .list {
            // Get the raw value and cast to array
            do {
                let profileKeysList: [AnyValue] = try await value.asType()
                var result: [Data] = []

                for keyValue in profileKeysList {
                    if keyValue.category == .bytes {
                        do {
                            let keyData: Data = try await keyValue.asType()
                            result.append(keyData)
                        } catch {
                            throw NodeError.invalidConfiguration("Profile public key not in expected bytes format")
                        }
                    } else {
                        throw NodeError.invalidConfiguration("Profile public key not in expected bytes format")
                    }
                }

                return result
            } catch {
                throw NodeError.invalidConfiguration("Profile public keys not in expected list format")
            }
        }
        throw NodeError.invalidConfiguration("Profile public keys not in expected list format")
    }

    /// Initialize network transport for remote communication
    private func initializeNetworkTransport() async throws {
        logger.trace("🔍 NETWORKING: Starting networking components...")

        guard supportsNetworking else {
            logger.trace("🔍 NETWORKING: Networking is disabled, skipping network initialization")
            return
        }

        guard let networkConfig = config.networkConfig else {
            throw NodeError.invalidConfiguration("Network configuration is required")
        }

        logger.trace("🔍 NETWORKING: Network config: \(networkConfig)")

        // Always require a transport (matches Rust behavior)
        guard !networkConfig.transportType.isEmpty else {
            throw NodeError.transportNotImplemented("Transport type is required - discovery-only mode not supported")
        }

        // Initialize the network transport
        if networkTransport == nil {
            logger.trace("🔍 NETWORKING: Initializing network transport...")

            // Create network transport using the factory pattern based on transport_type
            let transport = try await createTransport(networkConfig: networkConfig)

            logger.trace("🔍 NETWORKING: Starting transport...")
            try await transport.start()
            logger.trace("🔍 NETWORKING: Transport started successfully")

            // Store the transport
            networkTransport = transport

            // Note: Local peer info will be updated after discovery providers are created
        } else {
            logger.trace("🔍 NETWORKING: Transport already initialized, skipping")
        }

        // Initialize discovery if enabled
        if let discoveryOptions = networkConfig.discoveryOptions {
            logger.trace("🔍 NETWORKING: Initializing node discovery providers...")

            // Check if any providers are configured
            if networkConfig.discoveryProviders.isEmpty {
                throw NodeError.invalidConfiguration("No discovery providers configured")
            }

            logger.trace("🔍 NETWORKING: Found \(networkConfig.discoveryProviders.count) discovery providers")
            var discoveryProviders: [NodeDiscovery] = []

            // Iterate through all discovery providers and initialize each one
            for providerConfig in networkConfig.discoveryProviders {
                logger.trace("🔍 NETWORKING: Creating discovery provider: \(providerConfig)")

                // Create discovery provider instance (don't start yet)
                let discoveryProvider = try await createDiscoveryProvider(
                    providerConfig: providerConfig,
                    discoveryOptions: discoveryOptions
                )

                discoveryProviders.append(discoveryProvider)
            }

            // Store the discovery providers
            networkDiscoveryProviders = discoveryProviders
            logger.trace("🔍 NETWORKING: Stored \(discoveryProviders.count) discovery providers")

            // CRITICAL: Update local peer info for discovery announcements
            // This must be done after discovery providers are created but BEFORE starting them
            logger.trace("🔍 DISCOVERY: About to update local peer info for discovery announcements")
            try await updateLocalPeerInfoForDiscoveryAfterTransportStart()
            logger.trace("🔍 DISCOVERY: Completed updating local peer info for discovery announcements")

            // NOW start discovery providers with proper addresses
            for discoveryProvider in discoveryProviders {
                logger.trace("🔍 NETWORKING: Starting to announce on discovery provider")
                try await discoveryProvider.start()
                logger.trace("🔍 NETWORKING: Discovery provider started successfully")
            }
        } else {
            logger.trace("🔍 NETWORKING: No discovery options configured, skipping discovery")
        }

        logger.trace("🔍 NETWORKING: Networking components started successfully")
    }

    /// Create network transport based on configuration
    private func createTransport(networkConfig: NetworkConfig) async throws -> NodeTransport {
        logger.trace("Creating QUIC transport")

        // Get the current NodeInfo (this is just a getter, no transport update)
        let currentNodeInfo = try await getLocalNodeInfo()
        logger.trace("Got current NodeInfo with \(currentNodeInfo.nodeMetadata.services.count) services")

        // Note: The transport will be created with transport-scoped NodeInfo storage
        // The initial NodeInfo will be set when the transport is created

        // Create transport options matching Rust implementation
        let transportOptions = QuicTransportOptions(
            requestTimeoutSeconds: UInt64(config.requestTimeoutMs / 1000),
            bindAddr: networkConfig.bindAddress ?? "127.0.0.1:0"
        )
        logger.trace("Transport options: \(transportOptions)")

        // Create callbacks for network events
        let callbacks = TransportCallbacks(
            peerConnectedCallback: { [weak self] peerNodeId, nodeInfo in
                Task { @MainActor in
                    self?.logger.trace("🔍 HANDSHAKE: Peer connected callback triggered for peer: \(peerNodeId) at \(Date())")
                    self?.logger.trace("🔍 HANDSHAKE: NodeInfo received: \(nodeInfo)")
                    self?.logger.trace("🔍 HANDSHAKE: Raw FFI NodeInfo - services: \(nodeInfo.nodeMetadata.services.count), subscriptions: \(nodeInfo.nodeMetadata.subscriptions.count)")
                    self?.logger.trace("🔍 HANDSHAKE: This NodeInfo was sent by the peer during handshake - it should contain the peer's services")
                    for (index, service) in nodeInfo.nodeMetadata.services.enumerated() {
                        self?.logger.trace("🔍 HANDSHAKE: Service \(index): path=\(service.servicePath), name=\(service.name)")
                    }

                    // Convert SwiftFFI.NodeInfo to SwiftNode.NodeInfo
                    let swiftNodeInfo = NodeInfo(
                        nodePublicKey: nodeInfo.nodePublicKey,
                        networkIds: nodeInfo.networkIds,
                        addresses: nodeInfo.addresses,
                        nodeMetadata: {
                            let ffiMetadata = nodeInfo.nodeMetadata
                            self?.logger.trace("🔍 HANDSHAKE: Converting FFI metadata: \(ffiMetadata.services.count) services, \(ffiMetadata.subscriptions.count) subscriptions")

                            // Use SwiftFFI types directly (no conversion needed since they're type aliases)
                            return NodeMetadata(
                                services: ffiMetadata.services,
                                subscriptions: ffiMetadata.subscriptions
                            )
                        }(),
                        version: nodeInfo.version
                    )
                    self?.logger.trace("🔍 HANDSHAKE: Converted NodeInfo: \(swiftNodeInfo)")
                    self?.logger.trace("🔍 HANDSHAKE: Converted services: \(swiftNodeInfo.nodeMetadata.services)")
                    await self?.handlePeerConnected(peerNodeId: peerNodeId, nodeInfo: swiftNodeInfo)
                }
            },
            peerDisconnectedCallback: { [weak self] peerNodeId in
                Task { @MainActor in
                    await self?.handlePeerDisconnected(peerNodeId: peerNodeId)
                }
            },
            requestCallback: { [weak self, logger] requestId, incomingMessage in
                // Ensure self is available - cannot process without it
                guard let self else {
                    // This should never happen in normal operation
                    logger.error("❌ Request callback invoked but Node instance is nil - requestId: \(requestId)")
                    // Create minimal error response without accessing self
                    let errorValue = AnyValue.map([
                        "error": AnyValue.primitive(true),
                        "message": AnyValue.primitive("Node instance not available"),
                    ])
                    // Serialize without context (system-only, no encryption)
                    do {
                        let errorBytes = try await errorValue.serialize(context: nil)
                        return NetworkMessage(
                            sourceNodeId: incomingMessage.destinationNodeId, // Swap source/dest for response
                            destinationNodeId: incomingMessage.sourceNodeId,
                            messageType: 5, // MESSAGE_TYPE_RESPONSE
                            payload: NetworkMessagePayloadItem(
                                path: incomingMessage.payload.path,
                                payloadBytes: errorBytes,
                                correlationId: incomingMessage.payload.correlationId,
                                networkPublicKey: nil,
                                profilePublicKeys: []
                            )
                        )
                    } catch {
                        // Extremely rare: serialization failed even without encryption
                        logger.error("❌ Failed to serialize error response: \(error)")
                        // Return empty response as absolute last resort
                        return NetworkMessage(
                            sourceNodeId: incomingMessage.destinationNodeId,
                            destinationNodeId: incomingMessage.sourceNodeId,
                            messageType: 5,
                            payload: NetworkMessagePayloadItem(
                                path: incomingMessage.payload.path,
                                payloadBytes: Data(),
                                correlationId: incomingMessage.payload.correlationId,
                                networkPublicKey: nil,
                                profilePublicKeys: []
                            )
                        )
                    }
                }

                // The NetworkMessage has profilePublicKeys from FFI (Rust extracts .first() from wire format)
                // networkPublicKey is always looked up locally by Node, never trusted from wire

                // Process the network request and return the response (matching Rust pattern)
                // The callback is async, so we can directly await the result
                do {
                    let responseMessage = try await handleNetworkRequest(incomingMessage)
                    return responseMessage
                } catch {
                    // Create error response for transport callback
                    logger.error("Network request failed: \(error)")
                    // Create error response using proper HashMap serialization (matching Rust exactly)
                    let errorValue = AnyValue.map([
                        "error": AnyValue.primitive(true),
                        "message": AnyValue.primitive(error.localizedDescription),
                    ])

                    // Serialize error response using proper context (matching Rust exactly)
                    do {
                        let networkPublicKey = try await keysManager.getNetworkPublicKeyByNetworkId(networkId: incomingMessage.payload.path.components(separatedBy: ":").first ?? "default")
                        let resolver = try await getOrCreateResolver(incomingMessage.payload.profilePublicKeys)
                        let serializationContext = SerializationContext(
                            keystore: keysManager,
                            resolver: resolver,
                            networkPublicKey: networkPublicKey,
                            profilePublicKeys: incomingMessage.payload.profilePublicKeys
                        )
                        let errorBytes = try await errorValue.serialize(context: serializationContext)

                        // Return error response
                        return NetworkMessage(
                            sourceNodeId: incomingMessage.destinationNodeId, // Swap source/dest
                            destinationNodeId: incomingMessage.sourceNodeId,
                            messageType: 5, // MESSAGE_TYPE_RESPONSE
                            payload: NetworkMessagePayloadItem(
                                path: incomingMessage.payload.path,
                                payloadBytes: errorBytes,
                                correlationId: incomingMessage.payload.correlationId,
                                networkPublicKey: networkPublicKey,
                                profilePublicKeys: incomingMessage.payload.profilePublicKeys
                            )
                        )
                    } catch {
                        logger.error("Failed to serialize error response: \(error)")
                        // Last resort: return unencrypted error (this should be very rare)
                        do {
                            let fallbackError = AnyValue.map([
                                "error": AnyValue.primitive(true),
                                "message": AnyValue.primitive("Failed to serialize error response"),
                            ])
                            let fallbackBytes = try await fallbackError.serialize(context: nil)
                            return NetworkMessage(
                                sourceNodeId: incomingMessage.destinationNodeId,
                                destinationNodeId: incomingMessage.sourceNodeId,
                                messageType: 5, // MESSAGE_TYPE_RESPONSE
                                payload: NetworkMessagePayloadItem(
                                    path: incomingMessage.payload.path,
                                    payloadBytes: fallbackBytes,
                                    correlationId: incomingMessage.payload.correlationId,
                                    networkPublicKey: nil,
                                    profilePublicKeys: []
                                )
                            )
                        } catch {
                            // Extremely rare: even fallback serialization failed
                            logger.error("❌ Fallback serialization failed: \(error)")
                            // Return empty response as absolute last resort
                            return NetworkMessage(
                                sourceNodeId: incomingMessage.destinationNodeId,
                                destinationNodeId: incomingMessage.sourceNodeId,
                                messageType: 5,
                                payload: NetworkMessagePayloadItem(
                                    path: incomingMessage.payload.path,
                                    payloadBytes: Data(),
                                    correlationId: incomingMessage.payload.correlationId,
                                    networkPublicKey: nil,
                                    profilePublicKeys: []
                                )
                            )
                        }
                    }
                }
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

        logger.trace("Creating QuicTransport with nodeInfo: \(currentNodeInfo)")

        // Create the QuicTransport using the key manager
        let keyManager: FFIKeys = try config.getKeyManager()
        let transport = try await QuicTransport.create(
            keys: keyManager,
            nodeInfo: currentNodeInfo,
            options: transportOptions,
            callbacks: callbacks,
            logger: logger.child(component: .network)
        )

        logger.trace("QUIC transport created successfully")
        return transport
    }

    /// Create discovery provider based on configuration
    private func createDiscoveryProvider(
        providerConfig _: DiscoveryProviderConfig,
        discoveryOptions: SwiftFFI.DiscoveryOptions
    ) async throws -> SwiftFFI.NodeDiscovery {
        logger.trace("🔍 Creating real discovery provider with options: \(discoveryOptions)")

        // Get key manager for node public key
        guard let keyManager = config.getKeyManager() else {
            throw NodeError.missingKeyManager("Key manager not set in configuration")
        }

        // Get node public key for PeerInfo
        let nodePublicKey = try await keyManager.getNodePublicKey()
        logger.trace("🔍 Node public key: \(nodePublicKey.count) bytes")

        // Create PeerInfo for discovery (addresses will be set later when transport is available)
        let peerInfo = SwiftFFI.PeerInfo(
            publicKey: nodePublicKey,
            addresses: [] // Will be updated when transport address is available
        )
        logger.trace("🔍 Created PeerInfo for discovery")

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

        // Create Discovery instance with clean API - handles creation and initialization internally
        logger.trace("🔍 Creating Discovery instance with clean API")
        let discoveryProvider = try await SwiftFFI.Discovery(
            peerInfo: peerInfo,
            options: discoveryOptions,
            logger: logger.child(component: .network)
        )

        // Set the callbacks on the discovery provider
        await discoveryProvider.setCallbacks(discoveryCallbacks)
        logger.trace("🔍 Discovery provider created successfully")
        return discoveryProvider
    }

    /// Update local peer info for discovery announcements after transport is started
    private func updateLocalPeerInfoForDiscoveryAfterTransportStart() async throws {
        logger.trace("🔍 DISCOVERY: Updating local peer info for discovery announcements after transport start")

        // Get the local transport address
        guard let transport = networkTransport else {
            logger.warning("🔍 DISCOVERY: No transport available, cannot get local address")
            return
        }

        // Get key manager
        guard let keyManager = config.getKeyManager() else {
            logger.warning("🔍 DISCOVERY: No key manager available")
            return
        }

        do {
            // Get local address from transport
            let localAddr = try await transport.localAddr()
            logger.trace("🔍 DISCOVERY: Local address: \(localAddr)")

            // Get node public key from key manager
            let nodePublicKey = try await keyManager.getNodePublicKey()
            logger.trace("🔍 DISCOVERY: Node public key: \(nodePublicKey.count) bytes")

            // Create peer info
            let peerInfo = SwiftFFI.PeerInfo(
                publicKey: nodePublicKey,
                addresses: [localAddr]
            )
            logger.trace("🔍 DISCOVERY: Created PeerInfo with address: \(localAddr)")

            // Encode peer info to CBOR
            let encoder = CodableCBOREncoder()
            let peerInfoCbor = try encoder.encode(peerInfo)
            logger.trace("🔍 DISCOVERY: Peer info encoded to CBOR: \(peerInfoCbor.count) bytes")

            // Update all discovery providers with the peer info
            if let discoveryProviders = networkDiscoveryProviders {
                logger.trace("🔍 DISCOVERY: Found \(discoveryProviders.count) discovery providers to update")
                for (index, discoveryProvider) in discoveryProviders.enumerated() {
                    logger.trace("🔍 DISCOVERY: Updating discovery provider \(index + 1) of \(discoveryProviders.count)")
                    logger.trace("🔍 DISCOVERY: Calling updateLocalPeerInfo on discovery provider \(index + 1)")
                    try await discoveryProvider.updateLocalPeerInfo(peerInfoCbor: peerInfoCbor)
                    logger.trace("🔍 DISCOVERY: Successfully updated peer info for discovery provider \(index + 1)")
                }
            } else {
                logger.trace("🔍 DISCOVERY: No discovery providers available (networkDiscoveryProviders is nil)")
            }

            logger.trace("🔍 DISCOVERY: Local peer info updated successfully for all discovery providers")

        } catch {
            logger.error("🔍 DISCOVERY: Failed to update local peer info: \(error)")
            throw error
        }
    }

    /// Get local node information with current service metadata (GETTER ONLY)
    private func getLocalNodeInfo() async throws -> NodeInfo {
        // Get current services from the service registry with proper metadata including actions
        let currentServices = await serviceRegistry.getLocalServices()

        logger.trace("getLocalNodeInfo(): Found \(currentServices.count) local services")
        for (topicPath, serviceEntry) in currentServices {
            logger.trace("getLocalNodeInfo(): Service: \(topicPath.asString()) -> \(serviceEntry.service.name)")
        }

        // Get current subscriptions from the service registry (currently returns empty array)
        let currentSubscriptions = try? await serviceRegistry.getAllSubscriptions(includeInternalServices: false)
        let subscriptionMetadata = currentSubscriptions?.map(\.subscriptionMetadata) ?? []

        // Get proper service metadata from the service registry
        let serviceMetadata = try await serviceRegistry.getAllLocalServiceMetadata(includeInternalServices: false)

        // Create updated NodeInfo with current service metadata
        let nodeInfo = NodeInfo(
            nodePublicKey: localNodeInfo.nodePublicKey,
            networkIds: localNodeInfo.networkIds,
            addresses: localNodeInfo.addresses,
            nodeMetadata: NodeMetadata(
                services: Array(serviceMetadata.values),
                subscriptions: subscriptionMetadata
            ),
            version: localNodeInfo.version
        )

        logger.trace("NodeInfo with \(Array(serviceMetadata.values).count) services and \(subscriptionMetadata.count) subscriptions")

        return nodeInfo
    }

    /// Update the transport with current NodeInfo (SETTER ONLY)
    private func updateTransportNodeInfo() async throws {
        guard let transport = networkTransport else {
            logger.debug("No transport found (networkTransport is nil)")
            return
        }

        logger.trace("Transport found, updating with NodeInfo...")
        do {
            // Get current NodeInfo
            let currentNodeInfo = try await getLocalNodeInfo()

            logger.trace("Calling transport.updateLocalNodeInfo() with \(currentNodeInfo.nodeMetadata.services.count) services to transport")
            try await transport.updateLocalNodeInfo(nodeInfo: currentNodeInfo)
        } catch {
            logger.error("Failed to update transport with new NodeInfo: \(error)")
        }
    }

    /// Compact ID generation from public key
    // private func compactId(_ publicKey: Data) -> String {
    //     // Use the proper CompactId implementation from SwiftCommon
    //     // This matches the Rust implementation exactly
    //     return CompactId.compactId(from: publicKey)
    // }

    /// Get or create resolver for user profile keys
    /// Matches Rust: get_or_create_resolver
    private func getOrCreateResolver(_ profilePublicKeys: [Data]) async throws -> LabelResolver {
        // Use the node's cache instance to get or create resolver (matches Rust exactly)
        try await labelResolverCache.getOrCreateResolver(
            systemConfig: systemLabelConfig,
            userProfilePublicKeys: profilePublicKeys
        )
    }

    // MARK: - Network Message Handling

    /// Handle network request (async implementation matching Rust)
    private func handleNetworkRequest(_ message: NetworkMessage) async throws -> NetworkMessage {
        logger.debug("[handle_network_request] path: \(message.payload.path) correlation_id: \(message.payload.correlationId) profile_public_keys size: \(message.payload.profilePublicKeys.count)")

        // Deserialize the incoming payload (matching Rust exactly)
        let payload = try AnyValue.deserialize(
            message.payload.payloadBytes,
            keystore: keysManager
        )

        let paramsOption: AnyValue? = payload.isNull ? nil : payload

        // Parse topic path with proper error handling (matching Rust exactly)
        let topicPath: TopicPath
        do {
            topicPath = try TopicPath.fromFullPath(message.payload.path)
        } catch {
            logger.error("[handle_network_request] Failed to parse topic path: \(message.payload.path) correlation_id: \(message.payload.correlationId) : \(error)")
            throw NodeError.invalidPath("Failed to parse topic path: \(message.payload.path) correlation_id: \(message.payload.correlationId) : \(error)")
        }

        let networkId = topicPath.networkId
        let profilePublicKeys = message.payload.profilePublicKeys

        // Get network public key from key manager (matching Rust pattern exactly)
        // NOTE: Incoming message.payload.networkPublicKey is IGNORED (Rust does the same)
        let networkPublicKey = try await keysManager.getNetworkPublicKeyByNetworkId(networkId: networkId)

        // Make the local request using localRequest (matching Rust pattern exactly)
        do {
            let response = try await localRequest(
                topicPath.asString(),
                payload: paramsOption,
                options: nil
            )

            logger.debug("[handle_network_request] local request completed successfully correlation_id: \(message.payload.correlationId)")

            // Create dynamic resolver with user context for response serialization (matching Rust exactly)
            // For response serialization, we can use a system-only resolver since we're not encrypting new data
            let resolver = try await getOrCreateResolver(profilePublicKeys)

            let serializationContext = SerializationContext(
                keystore: keysManager,
                resolver: resolver,
                networkPublicKey: networkPublicKey,
                profilePublicKeys: profilePublicKeys
            )

            // Serialize the response data (matching Rust exactly)
            let serializedData = try await response.serialize(context: serializationContext)

            // Create response NetworkMessage (matching Rust exactly)
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
        } catch {
            // ERROR HANDLING (matching Rust exactly)
            logger.error("❌ [handle_network_request] Local request failed correlation_id: \(message.payload.correlationId) - Error: \(error)")

            // Create dynamic resolver with user context for error response serialization (matching Rust exactly)
            // For error response serialization, we can use a system-only resolver since we're not encrypting new data
            let resolver = try await getOrCreateResolver(profilePublicKeys)

            let serializationContext = SerializationContext(
                keystore: keysManager,
                resolver: resolver,
                networkPublicKey: networkPublicKey,
                profilePublicKeys: profilePublicKeys
            )

            // Create a proper error response using NodeError.networkRequestFailed (matching Rust exactly)
            let networkError = NodeError.networkRequestFailed(error.localizedDescription)
            var errorMap: [String: AnyValue] = [:]
            errorMap["error"] = AnyValue.primitive(true)
            errorMap["message"] = AnyValue.primitive(networkError.localizedDescription)
            let errorValue = AnyValue.map(errorMap)

            // Serialize the error value (matching Rust exactly)
            let serializedError = try await errorValue.serialize(context: serializationContext)

            // Create error response NetworkMessage (matching Rust exactly)
            return NetworkMessage(
                sourceNodeId: nodeId,
                destinationNodeId: message.sourceNodeId,
                messageType: 5, // MESSAGE_TYPE_RESPONSE
                payload: NetworkMessagePayloadItem(
                    path: message.payload.path,
                    payloadBytes: serializedError,
                    correlationId: message.payload.correlationId,
                    networkPublicKey: networkPublicKey,
                    profilePublicKeys: profilePublicKeys
                )
            )
        }
    }

    /// Handle peer connected event
    private func handlePeerConnected(peerNodeId: String, nodeInfo: NodeInfo) async {
        logger.trace("🔍 HANDSHAKE: handlePeerConnected called for peer: \(peerNodeId)")
        logger.trace("Peer connected: \(peerNodeId)")
        logger.trace("Peer NodeInfo: \(nodeInfo)")

        // Store peer info in remote_node_info (matching Rust implementation)
        logger.trace("🔍 HANDSHAKE: Storing peer info in remote_node_info")
        _ = await remoteNodeInfo.insert(nodeInfo, for: peerNodeId)
        logger.trace("🔍 HANDSHAKE: Peer info stored successfully")

        // Process service metadata from the peer's NodeInfo
        let nodeMetadata = nodeInfo.nodeMetadata
        logger.trace("🔍 HANDSHAKE: Processing peer service metadata: \(nodeMetadata.services.count) services")

        // Register remote services from the peer's metadata
        for service in nodeMetadata.services {
            logger.trace("🔍 HANDSHAKE: Registering remote service: \(service.name) from peer: \(peerNodeId)")

            // Create RemoteService instance and register it
            do {
                let serviceTopic = try TopicPath.new(service.servicePath, defaultNetwork: networkId)
                // Create RemoteServiceConfig and RemoteServiceDependencies
                let rsConfig = RemoteServiceConfig(
                    name: service.name,
                    serviceTopic: serviceTopic,
                    version: service.version,
                    description: service.description,
                    peerNodeId: peerNodeId,
                    requestTimeoutMs: 5000 // Default timeout
                )

                let rsDependencies = RemoteServiceDependencies(
                    networkTransport: networkTransport,
                    localNodeId: nodeId,
                    logger: logger,
                    keystore: keysManager,
                    labelResolverConfig: systemLabelConfig,
                    labelResolverCache: labelResolverCache
                )

                let remoteService = RemoteService(config: rsConfig, dependencies: rsDependencies)

                // Add actions to the service
                for action in service.actions {
                    try await remoteService.addAction(name: action.name, action: action)
                }
                _ = await serviceRegistry.registerRemoteService(remoteService)
            } catch {
                logger.error("Failed to create service topic for \(service.servicePath): \(error)")
            }

            // Register each action from the service
            for action in service.actions {
                let actionPath = "\(service.servicePath)/\(action.name)"
                logger.trace("🔍 HANDSHAKE: Registering remote action: \(actionPath) from peer: \(peerNodeId)")

                // Create a real network call handler (matching Rust implementation)
                let currentNetworkId = networkId
                let remoteHandler: ActionHandler = { [weak self] params, context in
                    return try await self?.makeRemoteNetworkCall(
                        topicPath: TopicPath.new(actionPath, defaultNetwork: currentNetworkId),
                        peerNodeId: peerNodeId,
                        params: params,
                        context: context
                    ) ?? AnyValue.null()
                }

                // Register the remote action handler
                do {
                    // Use proper TopicPath API like Rust: TopicPath::new(&action_path, &network_id)
                    let topicPath = try TopicPath.new(actionPath, defaultNetwork: networkId)
                    try await serviceRegistry.registerRemoteActionHandler(
                        topicPath: topicPath,
                        handler: remoteHandler
                    )
                    logger.trace("🔍 HANDSHAKE: Successfully registered remote action handler for: \(actionPath)")
                } catch {
                    logger.error("🔍 HANDSHAKE: Failed to register remote action handler for \(actionPath): \(error)")
                }
            }
        }
        logger.trace("🔍 HANDSHAKE: handlePeerConnected completed for peer: \(peerNodeId)")
    }

    /// Make a real remote network call (matching Rust implementation)
    private func makeRemoteNetworkCall(
        topicPath: TopicPath,
        peerNodeId: String,
        params: AnyValue?,
        context: RequestContext
    ) async throws -> AnyValue {
        logger.trace("🚀 [RemoteService] Starting remote request - Action: \(topicPath.asString()) Target: \(peerNodeId)")

        // Verify the peer exists
        guard await remoteNodeInfo.contains(peerNodeId) else {
            logger.warning("No NodeInfo found for peer: \(peerNodeId)")
            throw NodeError.peerNotFound("Peer not found: \(peerNodeId)")
        }

        // Generate a unique request ID
        let correlationId = UUID().uuidString

        // Get network transport
        guard let transport = networkTransport else {
            throw NodeError.serviceNotFound("Network transport not available")
        }

        // Serialize request parameters (matching Rust pattern)
        let paramsToSerialize = params ?? AnyValue.null()

        // Extract profile public keys from context metadata (matching Rust pattern exactly)
        let metadata = context.metadata
        let profilePublicKeys: [Data]
        if let profilePublicKeysValue = metadata["profile_public_keys"] {
            // Extract array of Data from AnyValue list
            profilePublicKeys = try await extractProfilePublicKeys(from: profilePublicKeysValue)
        } else {
            throw NodeError.invalidConfiguration("Profile public keys not found in metadata")
        }

        // Get network public key (matching Rust pattern exactly)
        let networkPublicKey = try await keysManager.getNetworkPublicKeyByNetworkId(networkId: networkId)

        // Create proper serialization context with encryption (matching Rust pattern exactly)
        let resolver = try await getOrCreateResolver(profilePublicKeys)
        let serializationContext = SerializationContext(
            keystore: keysManager,
            resolver: resolver,
            networkPublicKey: networkPublicKey,
            profilePublicKeys: profilePublicKeys
        )

        let paramsBytes = try await paramsToSerialize.serialize(context: serializationContext)

        // Make the network request (matching Rust network_transport.request call)
        let responseBytes = try await transport.request(
            path: topicPath.asString(),
            correlationId: correlationId,
            payload: paramsBytes,
            peerNodeId: peerNodeId,
            networkPublicKey: networkPublicKey,
            profilePublicKeys: profilePublicKeys
        )

        logger.trace("✅ [RemoteService] Response received successfully")

        // The response bytes are the full NetworkMessage CBOR, extract the payload
        let networkMessage = try CodableCBORDecoder().decode(NetworkMessage.self, from: responseBytes)

        // Deserialize the payload bytes to AnyValue
        let responseValue = try AnyValue.deserialize(networkMessage.payload.payloadBytes, keystore: keysManager)

        return responseValue
    }

    /// Handle peer disconnected event
    private func handlePeerDisconnected(peerNodeId: String) async {
        logger.trace("Peer disconnected: \(peerNodeId)")

        // Remove peer info from remote_node_info
        _ = await remoteNodeInfo.remove(peerNodeId)

        // Clean up remote services for this peer (matching Rust cleanup_disconnected_peer implementation)
        await serviceRegistry.removeRemoteServicesForPeer(peerId: peerNodeId)

        // Note: Remote action handlers cleanup is handled by ServiceRegistry
        logger.trace("Peer cleanup completed for: \(peerNodeId)")
    }

    // MARK: - Discovery Event Handlers

    /// Handle peer discovered event from discovery system
    private func handlePeerDiscovered(peerInfo: SwiftFFI.PeerInfo) async {
        // Early return if networking not supported (matches Rust)
        guard supportsNetworking else {
            logger.trace("🔍 DISCOVERY: Networking not supported, skipping peer discovery")
            return
        }

        // Use compact_id from public key (matches Rust exactly)
        let discoveredPeerId = CompactId.compactId(from: peerInfo.publicKey)

        logger.info("🔍 DISCOVERY: Discovery listener found node: \(discoveredPeerId)")

        // Debounce rapid duplicate announcements (matches Rust exactly)
        let shouldDebounce: Bool = if let lastSeen = await discoverySeenTimes.get(discoveredPeerId) {
            Date().timeIntervalSince(lastSeen) < 0.15 // 150ms
        } else {
            false
        }

        if shouldDebounce {
            logger.debug("🔍 DISCOVERY: Debounced discovery for \(discoveredPeerId)")
            // Do not early-return; small delay then continue to connect to ensure reconnection after restart
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
        } else {
            _ = await discoverySeenTimes.insert(Date(), for: discoveredPeerId)
        }

        // Attempt to connect to the discovered peer via transport (matches Rust exactly)
        if let transport = networkTransport {
            logger.trace("🔍 DISCOVERY: Attempting to connect to discovered peer via transport")
            do {
                try await transport.connectToPeer(peerInfo: peerInfo)
                logger.trace("🔍 DISCOVERY: Successfully initiated connection to peer \(discoveredPeerId)")
            } catch {
                logger.error("🔍 DISCOVERY: Connection failed to \(discoveredPeerId): \(error)")
            }
        } else {
            logger.warning("🔍 DISCOVERY: No network transport available for connection")
        }
    }

    /// Handle peer updated event from discovery system
    private func handlePeerUpdated(peerInfo: SwiftFFI.PeerInfo) async {
        // In Rust, both DiscoveryEvent::Discovered and DiscoveryEvent::Updated call handle_discovered_node
        // So we call the same method here
        await handlePeerDiscovered(peerInfo: peerInfo)
    }

    /// Handle peer lost event from discovery system
    private func handlePeerLost(nodeId: String) async {
        logger.info("🔍 DISCOVERY: Cleaning up disconnected peer: \(nodeId)")

        // 1) Remove remote subscriptions registered for this peer
        let subscriptionIds = await serviceRegistry.drainRemotePeerSubscriptions(peerId: nodeId)
        for subscriptionId in subscriptionIds {
            do {
                try await serviceRegistry.unsubscribeRemote(subscriptionId: subscriptionId)
            } catch {
                logger.error("🔍 DISCOVERY: Failed to unsubscribe remote subscription \(subscriptionId): \(error)")
            }
        }

        // 2) Remove remote services from this peer
        if let previousInfo = await remoteNodeInfo.get(nodeId) {
            for service in previousInfo.nodeMetadata.services {
                do {
                    let serviceTopicPath = try TopicPath.new(service.servicePath, defaultNetwork: service.networkId)
                    try await serviceRegistry.removeRemoteService(serviceTopic: serviceTopicPath)
                } catch {
                    logger.error("🔍 DISCOVERY: Failed to remove remote service \(service.servicePath): \(error)")
                }
            }
        }

        // 3) Remove from local cache
        _ = await remoteNodeInfo.remove(nodeId)

        // 4) Publish a local-only event indicating peer removal
        let disconnectedEventPath = "$registry/peer/\(nodeId)/disconnected"
        do {
            try await publish(
                topic: disconnectedEventPath,
                data: AnyValue.primitive(nodeId),
                options: PublishOptions.localOnly().withRetainFor(10.0)
            )
        } catch {
            logger.error("🔍 DISCOVERY: Failed to publish peer disconnected event: \(error)")
        }

        logger.trace("🔍 DISCOVERY: Peer lost handling completed for \(nodeId)")
    }

    /// Handle incoming network event
    private func handleNetworkEvent(
        requestId _: String,
        path: String,
        payload: Data,
        sourcePeerId _: String,
        correlationId: String?
    ) async {
        logger.trace("Handling network event: path=\(path), correlationId=\(correlationId ?? "nil")")

        do {
            // Parse the topic path
            let topicPath = try TopicPath.fromFullPath(path)

            // Deserialize payload using keystore (matching Rust pattern exactly)
            let deserializedPayload = try AnyValue.deserialize(
                payload,
                keystore: keysManager
            )

            let payloadOption = deserializedPayload.isNull ? nil : deserializedPayload

            // Create event context (currently unused since EventHandler doesn't take context)
            _ = EventContext(
                topicPath: topicPath,
                nodeDelegate: self,
                isLocal: false,
                logger: logger,
                deliveryOptions: nil
            )

            // Get subscribers for this topic
            let subscribers = await serviceRegistry.getLocalEventSubscribers(topicPath: topicPath)

            if subscribers.isEmpty {
                logger.trace("No subscribers found for topic: \(topicPath.rawPath)")
                return
            }

            // Dispatch to all subscribers
            for (_, handler, _) in subscribers {
                // Create event context for the handler
                let eventContext = EventContext(
                    topicPath: topicPath,
                    nodeDelegate: self,
                    isLocal: false,
                    logger: logger
                )
                try await handler(eventContext, payloadOption)
            }

            logger.trace("Network event dispatched successfully")

        } catch {
            logger.error("Network event handling failed: \(error)")
        }
    }

    /// Get all discovered peers (for testing)
    public func getDiscoveredPeers() async -> [NodeInfo] {
        let peerDict = await remoteNodeInfo.toDictionary()
        return Array(peerDict.values)
    }
}

// MARK: - QuicTransport NodeTransport Conformance

@MainActor
extension QuicTransport: NodeTransport {
    public func connectToPeer(peerInfo: SwiftFFI.PeerInfo) async throws {
        // Call the underlying SwiftFFI.QuicTransport connectPeer method
        try await connectPeer(peerInfo: peerInfo)
    }

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

    public func request(path: String, correlationId: String, payload: Data, peerNodeId: String, networkPublicKey _: Data?, profilePublicKeys _: [Data]) async throws -> Data {
        // Create TransportRequestParams for the request
        let requestParams = TransportRequestParams(
            path: path,
            correlationId: correlationId,
            payload: payload,
            destPeerId: peerNodeId
        )

        // Send the request and wait for response
        let responseBytes = try await request(requestParams)
        return responseBytes
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

    public func getServiceMetadata(servicePath: TopicPath) async throws -> ServiceMetadata? {
        try await serviceRegistry.getServiceMetadata(servicePath: servicePath)
    }

    public func getAllServiceMetadata(includeInternalServices: Bool, includeRemoteServices: Bool) async throws -> [String: ServiceMetadata] {
        try await serviceRegistry.getAllServiceMetadataRef(
            includeInternalServices: includeInternalServices,
            includeRemoteServices: includeRemoteServices
        )
    }

    public func getActionsMetadata(serviceTopicPath: TopicPath) async throws -> [ActionMetadata] {
        try await serviceRegistry.getActionsMetadata(serviceTopicPath: serviceTopicPath)
    }

    public func registerRemoteActionHandler(topicPath: TopicPath, handler: @escaping ActionHandler) async throws {
        try await serviceRegistry.registerRemoteActionHandler(topicPath: topicPath, handler: handler)
    }

    public func removeRemoteActionHandler(topicPath: TopicPath) async throws {
        try await serviceRegistry.removeRemoteActionHandler(topicPath: topicPath)
    }

    public func registerRemoteEventHandler(topicPath: TopicPath, handler: @escaping EventHandler) async throws {
        _ = try await serviceRegistry.registerRemoteEventSubscription(
            topicPath: topicPath,
            handler: { payload in try await handler(EventContext(topicPath: topicPath, nodeDelegate: self, isLocal: false, logger: self.logger), payload) },
            options: EventRegistrationOptions()
        )
    }

    public func removeRemoteEventHandler(topicPath: TopicPath) async throws {
        try await serviceRegistry.removeRemoteEventSubscription(topicPath: topicPath)
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

    public func remoteRequest(path: String, payload: AnyValue?, options: RequestOptions? = nil) async throws -> AnyValue {
        // This matches the Rust Node::remote_request implementation
        // Get remote handlers from service registry
        let topicPath = try TopicPath.new(path, defaultNetwork: networkId)
        let remoteHandlers = await serviceRegistry.getRemoteActionHandlers(topicPath: topicPath)

        if !remoteHandlers.isEmpty {
            logger.trace("Found \(remoteHandlers.count) remote handlers for: \(topicPath.asString())")

            // Extract profile public keys from options (matching Rust pattern exactly)
            let profilePublicKeys = options?.profilePublicKeys ?? []
            let profileKeysList: [AnyValue] = profilePublicKeys.map { AnyValue.primitive(Data($0)) }
            var metadata: [String: AnyValue] = [:]
            metadata["node_id"] = AnyValue.primitive(nodeId)
            metadata["profile_public_keys"] = AnyValue.list(profileKeysList)

            let requestContext = RequestContext(
                topicPath: topicPath,
                nodeDelegate: self,
                metadata: metadata,
                logger: logger
            )

            // Apply load balancing strategy to select a handler
            let loadBalancer = loadBalancer
            let handlerIndex = await loadBalancer.selectHandler(handlers: remoteHandlers, context: requestContext)

            guard let selectedIndex = handlerIndex else {
                logger.error("No handler available for action: \(topicPath.asString())")
                throw NodeError.serviceNotFound("No handler available for action: \(topicPath.asString())")
            }

            // Get the selected handler
            let handler = remoteHandlers[selectedIndex]

            logger.trace("Selected remote handler \(selectedIndex + 1) of \(remoteHandlers.count) for: \(topicPath.asString())")

            // Execute the selected handler (this will make the actual network call)
            do {
                let response = try await handler(payload, requestContext)
                return response
            } catch {
                logger.error("Remote handler execution failed: \(error)")
                throw error
            }
        }

        // No remote handlers found
        logger.error("No handler found for action: \(topicPath.asString())")
        throw NodeError.serviceNotFound("No handler found for action: \(topicPath.asString())")
    }

    // MARK: - Peer Management

    /// Add a new peer and process their capabilities (matches Rust add_new_peer)
    public func addNewPeer(nodeInfo: NodeInfo) async throws -> [RemoteService] {
        let capabilities = nodeInfo.nodeMetadata
        logger.info("Processing \(capabilities.services.count) services and \(capabilities.subscriptions.count) subscriptions from node \(CompactId.compactId(from: nodeInfo.nodePublicKey))")

        // Check if capabilities is empty
        if capabilities.services.isEmpty, capabilities.subscriptions.isEmpty {
            logger.info("Received empty capabilities list.")
            return [] // Nothing to process
        }

        // Get the local node ID
        let localPeerId = nodeId

        let peerNodeId = CompactId.compactId(from: nodeInfo.nodePublicKey)

        // Create RemoteService instances directly
        let rsConfig = CreateRemoteServicesConfig(
            services: capabilities.services,
            peerNodeId: peerNodeId,
            requestTimeoutMs: config.requestTimeoutMs
        )

        // Acquire the transport (should be initialized by now)
        guard let transportArc = networkTransport else {
            throw NodeError.transportNotAvailable("Network transport not available")
        }

        let rsDependencies = RemoteServiceDependencies(
            networkTransport: transportArc,
            localNodeId: localPeerId,
            logger: logger,
            keystore: keysManager,
            labelResolverConfig: systemLabelConfig,
            labelResolverCache: labelResolverCache
        )

        let remoteServices: [RemoteService]
        do {
            remoteServices = try await RemoteService.createFromCapabilities(config: rsConfig, dependencies: rsDependencies)
        } catch {
            logger.error("Failed to create remote services from capabilities: \(error)")
            throw error
        }

        // Register each service and initialize it to register its handlers
        for service in remoteServices {
            // Register the service instance with the registry
            let registered = await serviceRegistry.registerRemoteService(service)
            if !registered {
                continue // Skip initialization if registration fails
            }

            // Create RemoteLifecycleContext for the service to register its handlers
            // The context needs a reference back to the registry (as ServiceRegistry)
            // The Node itself implements RegistryDelegate but RemoteLifecycleContext needs ServiceRegistry

            // The TopicPath for the context should represent the service itself
            let serviceTopicPath: TopicPath
            do {
                serviceTopicPath = try TopicPath.new(service.path, defaultNetwork: networkId)
            } catch {
                logger.error("Failed to create TopicPath for remote service init: \(error)")
                continue
            }

            // Pass TopicPath by reference
            let context = RemoteLifecycleContext(serviceTopic: serviceTopicPath, logger: logger, registryDelegate: serviceRegistry)

            // Initialize the service - this triggers handler registration via the context
            do {
                try await service.initService(context: context)
            } catch {
                logger.error("Failed to initialize remote service '\(service.path)' (handler registration): \(error)")
            }

            try await serviceRegistry.updateRemoteServiceState(serviceTopic: serviceTopicPath, state: .running)

            // Publish local-only running state for remote service so local components can await readiness
            do {
                try await publish(
                    topic: "$registry/services/\(serviceTopicPath.servicePath)/state/running",
                    data: AnyValue.primitive(serviceTopicPath.asString()),
                    options: PublishOptions.localOnly().withRetainFor(120)
                )
            } catch {
                logger.error("Failed to publish remote service running state: \(error)")
            }
        }

        // Handle remote node subscriptions - only for services that exist locally
        for subscription in capabilities.subscriptions {
            let path = subscription.path
            let topicPath: TopicPath
            do {
                topicPath = try TopicPath.fromFullPath(path)
            } catch {
                logger.warning("Failed to parse subscription path '\(path)': \(error)")
                continue
            }

            // Skip if our node does not participate in the requested network
            if !networkIds.contains(topicPath.networkId) {
                logger.debug("Ignoring remote subscription \(path) - network id not supported")
                continue
            }

            // Create serialization context for this subscription
            let networkId = topicPath.networkId
            // Resolve network ID to public key
            let networkPublicKey: Data
            do {
                networkPublicKey = try await keysManager.getNetworkPublicKeyByNetworkId(networkId: networkId)
            } catch {
                logger.warning("Failed to resolve network public key for \(networkId): \(error)")
                continue
            }

            // Create dynamic resolver for remote subscription (system context)
            let emptyProfileKeys: [Data] = []
            let resolver = try await getOrCreateResolver(emptyProfileKeys)

            let serializationContext = SerializationContext(
                keystore: keysManager,
                resolver: resolver,
                networkPublicKey: networkPublicKey,
                profilePublicKeys: []
            )

            // Create event handler forwarding events to remote peer
            let eventHandler: RemoteEventHandler = { [weak self] eventData in
                guard let self else { return }
                let correlationId = UUID().uuidString
                logger.debug("🚀 [RemoteEvent] Sending remote event - Event: \(topicPath), Target: \(peerNodeId) correlation_id: \(correlationId)")

                do {
                    let topicPathStr = topicPath.asString()
                    // Serialize the event data
                    let payloadBytes = try await (eventData ?? AnyValue.null()).serialize(context: serializationContext)

                    try await transportArc.publish(
                        topic: topicPathStr,
                        payload: payloadBytes,
                        options: PublishOptions()
                    )

                    logger.debug("✅ [RemoteEvent] Event forwarded - Event: \(topicPath), Target: \(peerNodeId) correlation_id: \(correlationId)")
                } catch {
                    logger.error("Failed to forward event to remote peer: \(error)")
                    throw error
                }
            }

            do {
                let subscriptionId = try await serviceRegistry.registerRemoteEventSubscription(
                    topicPath: topicPath,
                    handler: eventHandler,
                    options: EventRegistrationOptions()
                )
                await serviceRegistry.upsertRemotePeerSubscription(peerId: peerNodeId, path: topicPath, subId: subscriptionId)
            } catch {
                logger.warning("Failed to register remote subscription \(path) for peer \(peerNodeId): \(error)")
            }
        }

        logger.info("Successfully processed \(remoteServices.count) remote services and \(capabilities.subscriptions.count) remote subscriptions from node \(CompactId.compactId(from: nodeInfo.nodePublicKey))")

        return remoteServices
    }

    /// Update peer capabilities by diffing old and new peer info (matches Rust update_peer_capabilities exactly)
    public func updatePeerCapabilities(oldPeer: NodeInfo, newPeer: NodeInfo) async throws {
        let peerNodeId = CompactId.compactId(from: oldPeer.nodePublicKey)

        // FIRST: Diff services
        let oldServices: Set<String> = Set(oldPeer.nodeMetadata.services.map { service in
            "\(service.networkId):\(service.servicePath)"
        })
        let newServices: Set<String> = Set(newPeer.nodeMetadata.services.map { service in
            "\(service.networkId):\(service.servicePath)"
        })

        // Services to add
        let servicesToAdd = newServices.subtracting(oldServices)
        for serviceKey in servicesToAdd {
            // Find the actual service metadata for this key
            if let serviceMetadata = newPeer.nodeMetadata.services.first(where: { service in
                serviceKey == "\(service.networkId):\(service.servicePath)"
            }) {
                logger.info("Adding new remote service: \(serviceKey) from peer: \(peerNodeId)")

                // Create and register the new remote service (reuse logic from add_new_peer)
                guard let transportArc = networkTransport else {
                    throw NodeError.transportNotAvailable("Network transport not available")
                }
                let localPeerId = nodeId

                let rsConfig = CreateRemoteServicesConfig(
                    services: [serviceMetadata],
                    peerNodeId: peerNodeId,
                    requestTimeoutMs: config.requestTimeoutMs
                )

                let rsDependencies = RemoteServiceDependencies(
                    networkTransport: transportArc,
                    localNodeId: localPeerId,
                    logger: logger,
                    keystore: keysManager,
                    labelResolverConfig: systemLabelConfig,
                    labelResolverCache: labelResolverCache
                )

                do {
                    let remoteServices = try await RemoteService.createFromCapabilities(config: rsConfig, dependencies: rsDependencies)

                    for service in remoteServices {
                        // Register the service instance with the registry
                        let registered = await serviceRegistry.registerRemoteService(service)
                        if !registered {
                            continue
                        }

                        // Initialize the service - this triggers handler registration via the context
                        let serviceTopicPath: TopicPath
                        do {
                            serviceTopicPath = try TopicPath.new(service.path, defaultNetwork: networkId)
                        } catch {
                            logger.error("Failed to create TopicPath for remote service init: \(error)")
                            continue
                        }

                        let context = RemoteLifecycleContext(serviceTopic: serviceTopicPath, logger: logger, registryDelegate: serviceRegistry)

                        do {
                            try await service.initService(context: context)
                        } catch {
                            logger.error("Failed to initialize remote service '\(service.path)': \(error)")
                        }

                        try await serviceRegistry.updateRemoteServiceState(serviceTopic: serviceTopicPath, state: .running)

                        // Publish local-only running state for remote service so local components can await readiness
                        do {
                            try await publish(
                                topic: "$registry/services/\(serviceTopicPath.servicePath)/state/running",
                                data: AnyValue.primitive(serviceTopicPath.asString()),
                                options: PublishOptions.localOnly().withRetainFor(120)
                            )
                        } catch {
                            logger.error("Failed to publish remote service running state: \(error)")
                        }

                        logger.info("Published local-only running for remote service \(serviceTopicPath)")
                    }
                } catch {
                    logger.error("Failed to create remote services from capabilities: \(error)")
                }
            }
        }

        // Services to remove
        let servicesToRemove = oldServices.subtracting(newServices)
        for serviceKey in servicesToRemove {
            // Find the actual service metadata for this key
            if let serviceMetadata = oldPeer.nodeMetadata.services.first(where: { service in
                serviceKey == "\(service.networkId):\(service.servicePath)"
            }) {
                logger.info("Removing remote service: \(serviceKey) from peer: \(peerNodeId)")

                let servicePath: TopicPath
                do {
                    servicePath = try TopicPath.new(serviceMetadata.servicePath, defaultNetwork: serviceMetadata.networkId)
                } catch {
                    logger.warning("Failed to create TopicPath for service removal: \(error)")
                    continue
                }

                do {
                    try await serviceRegistry.removeRemoteService(serviceTopic: servicePath)
                } catch {
                    logger.warning("Failed to remove remote service \(serviceKey): \(error)")
                }
            }
        }

        // SECOND: Diff subscriptions
        let oldSet: Set<String> = Set(oldPeer.nodeMetadata.subscriptions.map(\.path))
        let newSet: Set<String> = Set(newPeer.nodeMetadata.subscriptions.map(\.path))

        logger.debug("Subscription diffing for peer \(peerNodeId): old_set=\(oldSet), new_set=\(newSet)")

        guard let transportArc = networkTransport else {
            throw NodeError.transportNotAvailable("Network transport not available")
        }

        // Paths to add
        let pathsToAdd = newSet.subtracting(oldSet)
        for path in pathsToAdd {
            logger.info("Adding new remote subscription: \(path) for peer: \(peerNodeId)")

            // Create remote handler same as add_new_peer logic (reuse closure building)
            let topicPath: TopicPath
            do {
                topicPath = try TopicPath.fromFullPath(path)
            } catch {
                logger.warning("Invalid topic path \(path): \(error)")
                continue
            }

            let networkId = topicPath.networkId

            // Resolve network ID to public key
            let networkPublicKey: Data
            do {
                networkPublicKey = try await keysManager.getNetworkPublicKeyByNetworkId(networkId: networkId)
            } catch {
                logger.warning("Failed to resolve network public key for \(networkId): \(error)")
                continue
            }

            // Create dynamic resolver for remote subscription (system context)
            let emptyProfileKeys: [Data] = []
            let resolver = try await getOrCreateResolver(emptyProfileKeys)

            let serializationContext = SerializationContext(
                keystore: keysManager,
                resolver: resolver,
                networkPublicKey: networkPublicKey,
                profilePublicKeys: []
            )

            // Create event handler forwarding events to remote peer
            let eventHandler: RemoteEventHandler = { [weak self] eventData in
                guard let self else { return }
                let correlationId = UUID().uuidString
                logger.debug("🚀 [RemoteEvent] Sending remote event - Event: \(topicPath), Target: \(peerNodeId) correlation_id: \(correlationId)")

                do {
                    let topicPathStr = topicPath.asString()
                    // Serialize the event data
                    let payloadBytes = try await (eventData ?? AnyValue.null()).serialize(context: serializationContext)

                    try await transportArc.publish(
                        topic: topicPathStr,
                        payload: payloadBytes,
                        options: PublishOptions()
                    )

                    logger.debug("✅ [RemoteEvent] Event forwarded - Event: \(topicPath), Target: \(peerNodeId) correlation_id: \(correlationId)")
                } catch {
                    logger.error("Failed to forward event to remote peer: \(error)")
                    throw error
                }
            }

            do {
                let subscriptionId = try await serviceRegistry.registerRemoteEventSubscription(
                    topicPath: topicPath,
                    handler: eventHandler,
                    options: EventRegistrationOptions()
                )
                await serviceRegistry.upsertRemotePeerSubscription(peerId: peerNodeId, path: topicPath, subId: subscriptionId)
            } catch {
                logger.warning("Failed to register remote subscription \(path) for peer \(peerNodeId): \(error)")
            }
        }

        // Paths to remove
        let pathsToRemove = oldSet.subtracting(newSet)
        for path in pathsToRemove {
            logger.info("Removing remote subscription: \(path) for peer: \(peerNodeId)")

            let topicPath: TopicPath
            do {
                topicPath = try TopicPath.fromFullPath(path)
            } catch {
                logger.warning("Failed to parse topic path \(path): \(error)")
                continue
            }

            if let subId = await serviceRegistry.removeRemotePeerSubscription(peerId: peerNodeId, path: topicPath) {
                do {
                    try await serviceRegistry.unsubscribeRemote(subscriptionId: subId)
                } catch {
                    logger.warning("Failed to unsubscribe remote subscription \(subId): \(error)")
                }
            }
        }
    }
}

// MARK: - Node Errors

/// Errors that can occur during node operations
public enum NodeError: Error, LocalizedError, Sendable {
    case missingKeyManager(String)
    case missingNodePublicKey(String)
    case serviceRegistrationFailed(String)
    case networkInitializationFailed(String)
    case invalidConfiguration(String)
    case transportNotImplemented(String)
    case transportNotAvailable(String)
    case discoveryNotImplemented(String)
    case invalidServicePath(String)
    case serviceInitializationFailed(String)
    case peerNotFound(String)
    case invalidPath(String)
    case serviceNotFound(String)
    case timeout(String)
    case networkRequestFailed(String)

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
        case let .transportNotAvailable(message):
            "Network transport not available: \(message)"
        case let .discoveryNotImplemented(message):
            "Discovery not implemented: \(message)"
        case let .peerNotFound(message):
            "Peer not found: \(message)"
        case let .invalidPath(message):
            "Invalid path: \(message)"
        case let .serviceNotFound(message):
            "Service not found: \(message)"
        case let .timeout(message):
            "Timeout: \(message)"
        case let .networkRequestFailed(message):
            "Network request failed: \(message)"
        }
    }
}
