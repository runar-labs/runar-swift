import Foundation
import RunarSerializer
import SwiftCBOR
import SwiftCommon
import SwiftFFI

// MARK: - FFI Integration

/// Type alias for FFIKeys to use real NodeKeyManager from swift-ffi
public typealias FFIKeys = NodeKeyManager

// MARK: - Missing Types and Protocols

/// Protocol for network transport implementations
public protocol NodeTransport: AnyObject {
    func start() throws
    func stop() throws
    func sendRequest(path: String, payload: Data, correlationId: String) throws
    func completeRequest(requestId: String, responsePayload: Data, profilePublicKey: Data?) throws
    func publish(topic: String, payload: Data, options: PublishOptions) throws
    func subscribe(topic: String, subscriptionId: String) throws
    func unsubscribe(subscriptionId: String) throws
    func pollEvent() throws -> Data?
    func localAddr() throws -> String
    func updateLocalNodeInfo(_ nodeInfo: Data) throws
}

/// Protocol for load balancing strategies
public protocol LoadBalancingStrategy: Sendable {
    mutating func selectHandler(handlers: [String]) -> String?
}

/// Round-robin load balancer implementation
public struct RoundRobinLoadBalancer: LoadBalancingStrategy {
    private let lock = NSLock()
    private var currentIndex: Int = 0

    public init() {}

    public mutating func selectHandler(handlers: [String]) -> String? {
        guard !handlers.isEmpty else { return nil }

        lock.lock()
        defer { lock.unlock() }

        let selected = handlers[currentIndex % handlers.count]
        currentIndex += 1
        return selected
    }
}

/// Protocol for node discovery
public protocol NodeDiscovery: Sendable {
    func start() throws
    func stop() throws
}

/// Placeholder transport implementation
public final class PlaceholderTransport: NodeTransport {
    public init() {}
    
    public func start() throws {
        // Placeholder implementation
    }
    
    public func stop() throws {
        // Placeholder implementation
    }
    
    public func sendRequest(path: String, payload: Data, correlationId: String) throws {
        // Placeholder implementation
    }
    
    public func completeRequest(requestId: String, responsePayload: Data, profilePublicKey: Data?) throws {
        // Placeholder implementation
    }
    
    public func publish(topic: String, payload: Data, options: PublishOptions) throws {
        // Placeholder implementation
    }
    
    public func subscribe(topic: String, subscriptionId: String) throws {
        // Placeholder implementation
    }
    
    public func unsubscribe(subscriptionId: String) throws {
        // Placeholder implementation
    }
    
    public func pollEvent() throws -> Data? {
        // Placeholder implementation
        return nil
    }
    
    public func localAddr() throws -> String {
        // Placeholder implementation
        return "127.0.0.1:0"
    }
    
    public func updateLocalNodeInfo(_ nodeInfo: Data) throws {
        // Placeholder implementation
    }
}

/// Placeholder discovery implementation
public final class PlaceholderDiscovery: NodeDiscovery {
    public init() {}
    
    public func start() throws {
        // Placeholder implementation
    }
    
    public func stop() throws {
        // Placeholder implementation
    }
}

/// Type alias for ResolverCache to use real SerializationRegistry from RunarSerializer
public typealias ResolverCache = SerializationRegistry

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
public struct DiscoveryOptions: Sendable, Codable {
    public let enabled: Bool
    public let interval: TimeInterval
    
    public init(enabled: Bool = true, interval: TimeInterval = 5.0) {
        self.enabled = enabled
        self.interval = interval
    }
}

/// Registry Service - provides information about registered services
public final class RegistryService: AbstractService {
    public let name: String = "RegistryService"
    public let version: String = "1.0.0"
    public let path: String = "registry"
    public let description: String = "Internal registry service"
    
    public let logger: RunarLogger
    private let nodeDelegate: NodeDelegate
    
    public var networkId: String?
    public private(set) var state: ServiceState = .created
    
    public init(logger: RunarLogger, nodeDelegate: NodeDelegate) {
        self.logger = logger
        self.nodeDelegate = nodeDelegate
    }
    
    public func initService(_ context: LifecycleContext) async throws {
        // Register registry actions
        try await context.registerAction("services/list") { _ in
            // Return list of all services
            return AnyValue.map([:])
        }
        
        try await context.registerAction("services/{service_path}") { params in
            // Return service information
            return AnyValue.map([:])
        }
        
        try await context.registerAction("services/{service_path}/state") { params in
            // Return service state
            return AnyValue.map([:])
        }
        
        state = .initialized
    }
    
    public func start(_: LifecycleContext) async throws {
        state = .running
        logger.info("Registry service started")
    }
    
    public func stop(_: LifecycleContext) async throws {
        state = .stopped
        logger.info("Registry service stopped")
    }
}

/// Keys Service - provides key management functionality
public final class KeysService: AbstractService {
    public let name: String = "KeysService"
    public let version: String = "1.0.0"
    public let path: String = "keys"
    public let description: String = "Internal keys service"
    
    public let logger: RunarLogger
    private let nodeDelegate: NodeDelegate
    
    public var networkId: String?
    public private(set) var state: ServiceState = .created
    
    public init(logger: RunarLogger, nodeDelegate: NodeDelegate) {
        self.logger = logger
        self.nodeDelegate = nodeDelegate
    }
    
    public func initService(_ context: LifecycleContext) async throws {
        // Register keys actions
        try await context.registerAction("ensure_symmetric_key") { params in
            // Ensure symmetric key exists
            return AnyValue.map([:])
        }
        
        try await context.registerAction("get_public_key") { params in
            // Get public key
            return AnyValue.map([:])
        }
        
        state = .initialized
    }
    
    public func start(_: LifecycleContext) async throws {
        state = .running
        logger.info("Keys service started")
    }
    
    public func stop(_: LifecycleContext) async throws {
        state = .stopped
        logger.info("Keys service stopped")
    }
}

/// Protocol for node delegate
public protocol NodeDelegate: AnyObject {
    func registerAction(networkId: String, servicePath: String, action: String, handler: @escaping ActionHandler) async throws
    func unregisterAction(networkId: String, servicePath: String, action: String) async throws
    func subscribeToEvents(networkId: String, servicePath: String, handler: @escaping EventHandler) async throws -> String
    func unsubscribeFromEvents(subscriptionId: String) async throws
    func subscribe(topic: String, options: EventRegistrationOptions?, callback: @escaping EventHandler) async throws -> String
    func publish(topic: String, data: AnyValue?) async throws
}

/// Action handler type
public typealias ActionHandler = @Sendable (AnyValue?) async throws -> AnyValue

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
public struct LoggingConfig: Sendable, Codable {
    /// Default log level for all runar modules
    public let defaultLevel: LogLevel

    public init(defaultLevel: LogLevel = .info) {
        self.defaultLevel = defaultLevel
    }

    /// Create a default info-level logging configuration
    public static func defaultInfo() -> LoggingConfig {
        LoggingConfig(defaultLevel: .info)
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
    public let discoveryOptions: DiscoveryOptions?
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
        discoveryOptions: DiscoveryOptions? = nil,
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
/// - `loggingConfig`: Info level logging
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
    public var loggingConfig: LoggingConfig?

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
        loggingConfig = LoggingConfig.defaultInfo() // Default to Info logging
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
    ///     .withLoggingConfig(LoggingConfig.defaultInfo())
    /// ```
    public func withLoggingConfig(_ config: LoggingConfig) -> NodeConfig {
        var newConfig = self
        newConfig.loggingConfig = config
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

// MARK: - Node

/// Main Node implementation matching Rust structure
public final class Node {
    // MARK: - Core Properties

    /// Debounce state for notify_node_change
    private let debounceNotifyTask: NSLock
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
    private let remoteNodeInfo: NSLock
    private var _remoteNodeInfo: [String: NodeInfo] = [:]

    /// Debounce repeated discovery events per peer
    private let discoverySeenTimes: NSLock
    private var _discoverySeenTimes: [String: Date] = [:]

    /// Logger instance
    public let logger: RunarLogger

    /// Flag indicating if the node is running
    private let running: NSLock
    private var _running: Bool = false

    /// Flag indicating if this node supports networking
    /// This is set when networking is enabled in the config
    public let supportsNetworking: Bool

    /// Network transport for connecting to remote nodes
    private let networkTransport: NSLock
    private var _networkTransport: (any NodeTransport)?

    /// Network discovery providers
    private let networkDiscoveryProviders: NSLock
    private var _networkDiscoveryProviders: [NodeDiscovery]?

    /// Load balancer for selecting remote handlers
    private let loadBalancer: NSLock
    private var _loadBalancer: LoadBalancingStrategy?

    /// System label configuration for dynamic resolver creation
    public let systemLabelConfig: LabelResolverConfig

    /// Per-node label resolver cache for better concurrency and isolation
    public let labelResolverCache: ResolverCache

    /// Registry version for tracking changes
    private let registryVersion: NSLock
    private var _registryVersion: Int64 = 0

    /// Key manager containing node credentials
    public let keysManager: FFIKeys

    /// Service tasks for tracking service lifecycle
    private let serviceTasks: NSLock
    private var _serviceTasks: [ServiceTask] = []

    /// Local node information
    public let localNodeInfo: NodeInfo

    /// Retained event store: exact full topic -> deque of (timestamp, data)
    private let retainedEvents: NSLock
    private var _retainedEvents: [String: [RetainedEventEntry]] = [:]

    /// Index of exact topics for wildcard lookups
    private let retainedIndex: NSLock
    private var _retainedIndex: PathTrie<String> = PathTrie()

    // MARK: - Computed Properties

    /// Check if the node is currently running
    public var isRunning: Bool {
        running.lock()
        defer { running.unlock() }
        return _running
    }

    /// Get the current registry version
    public var currentRegistryVersion: Int64 {
        registryVersion.lock()
        defer { registryVersion.unlock() }
        return _registryVersion
    }

    /// Get the current service tasks
    public var currentServiceTasks: [ServiceTask] {
        serviceTasks.lock()
        defer { serviceTasks.unlock() }
        return _serviceTasks
    }

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
        if let loggingConfig = config.loggingConfig {
            // Apply logging configuration here
            // This would integrate with the logging system
        } else {
            // Apply default Info logging when no configuration is provided
            let defaultConfig = LoggingConfig.defaultInfo()
            // Apply default logging configuration
        }

        // Clone fields before moving config
        let defaultNetworkId = config.defaultNetworkId
        let networkingEnabled = config.networkConfig != nil

        var networkIds = config.networkIds
        networkIds.append(defaultNetworkId)
        networkIds = Array(Set(networkIds)) // Remove duplicates

        let logger = RunarLogger(component: .node)
        let serviceRegistry = ServiceRegistry(logger: logger)

        // Extract the key manager from config
        guard let keysManager = config.getKeyManager() else {
            throw NodeError.missingKeyManager("Failed to load node credentials.")
        }

        let nodePublicKey = try await keysManager.getNodePublicKey()

        let nodeId = CompactId.compactId(from: nodePublicKey)
        // logger.setContext(nodeId) // RunarLogger doesn't have setContext method

        logger.info("Successfully loaded existing node credentials.")

        let localNodeInfo = NodeInfo(
            nodePublicKey: nodePublicKey,
            networkIds: networkIds,
            addresses: [],
            nodeMetadata: NodeMetadata(services: [], subscriptions: []),
            version: 0
        )

        let node = Node(
            debounceNotifyTask: NSLock(),
            debounceTask: nil as Task<Void, Never>?,
            networkId: defaultNetworkId,
            networkIds: networkIds,
            nodeId: nodeId,
            nodePublicKey: nodePublicKey,
            config: config,
            serviceRegistry: serviceRegistry,
            remoteNodeInfo: NSLock(),
            discoverySeenTimes: NSLock(),
            logger: logger,
            running: NSLock(),
            _running: false,
            supportsNetworking: networkingEnabled,
            networkTransport: NSLock(),
            _networkTransport: nil as NodeTransport?,
            networkDiscoveryProviders: NSLock(),
            _networkDiscoveryProviders: nil as [NodeDiscovery]?,
            loadBalancer: NSLock(),
            _loadBalancer: nil as LoadBalancingStrategy?,
            systemLabelConfig: config.labelResolverConfig,
            labelResolverCache: SerializationRegistry.shared,
            registryVersion: NSLock(),
            _registryVersion: 0,
            keysManager: keysManager,
            serviceTasks: NSLock(),
            _serviceTasks: [],
            localNodeInfo: localNodeInfo,
            retainedEvents: NSLock(),
            retainedIndex: NSLock(),
            _retainedIndex: PathTrie<String>()
        )

        // Register the registry service
        let registryService = RegistryService(
            logger: logger,
            nodeDelegate: node
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
        debounceNotifyTask: NSLock,
        debounceTask: Task<Void, Never>?,
        networkId: String,
        networkIds: [String],
        nodeId: String,
        nodePublicKey: Data,
        config: NodeConfig,
        serviceRegistry: ServiceRegistry,
        remoteNodeInfo: NSLock,
        discoverySeenTimes: NSLock,
        logger: RunarLogger,
        running: NSLock,
        _running: Bool,
        supportsNetworking: Bool,
        networkTransport: NSLock,
        _networkTransport: (any NodeTransport)?,
        networkDiscoveryProviders: NSLock,
        _networkDiscoveryProviders: [NodeDiscovery]?,
        loadBalancer: NSLock,
        _loadBalancer: LoadBalancingStrategy?,
        systemLabelConfig: LabelResolverConfig,
        labelResolverCache: ResolverCache,
        registryVersion: NSLock,
        _registryVersion: Int64,
        keysManager: FFIKeys,
        serviceTasks: NSLock,
        _serviceTasks: [ServiceTask],
        localNodeInfo: NodeInfo,
        retainedEvents: NSLock,
        retainedIndex: NSLock,
        _retainedIndex: PathTrie<String>
    ) {
        self.debounceNotifyTask = debounceNotifyTask
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
        self._running = _running
        self.supportsNetworking = supportsNetworking
        self.networkTransport = networkTransport
        self._networkTransport = _networkTransport
        self.networkDiscoveryProviders = networkDiscoveryProviders
        self._networkDiscoveryProviders = _networkDiscoveryProviders
        self.loadBalancer = loadBalancer
        self._loadBalancer = _loadBalancer
        self.systemLabelConfig = systemLabelConfig
        self.labelResolverCache = labelResolverCache
        self.registryVersion = registryVersion
        self._registryVersion = _registryVersion
        self.keysManager = keysManager
        self.serviceTasks = serviceTasks
        self._serviceTasks = _serviceTasks
        self.localNodeInfo = localNodeInfo
        self.retainedEvents = retainedEvents
        self.retainedIndex = retainedIndex
        self._retainedIndex = _retainedIndex
    }

    // MARK: - Core Methods

    /// Get or create resolver using node's cache instance
    private func getOrCreateResolver(userProfileKeys: [Data]) throws -> LabelResolver {
        try LabelResolver.createContextResolver(
            systemConfig: systemLabelConfig,
            userProfilePublicKeys: userProfileKeys
        )
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
        service.networkId = networkId
        
        // Register the service instance with the registry
        try await serviceRegistry.registerServiceInstance(
            service: service,
            networkId: networkId
        )

        let topic = "\(networkId):\(service.path)"
        let context = LifecycleContext(
            networkId: networkId,
            servicePath: service.path,
            config: nil,
            logger: logger,
            nodeDelegate: self
        )

        try await service.initService(context)

        if isRunning {
            // Node already started: start service immediately and mark running
            try await service.start(context)
            try await serviceRegistry.updateLocalServiceState(
                servicePath: service.path,
                newState: ServiceState.running
            )
            logger.info("Service started: \(topic)")
        } else {
            // Keep instance to start later during node.start()
            // This would be handled by the service registry
            logger.info("Service initialized: \(topic)")
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
        logger.info("Node started networkId=\(networkId)")

        // Start all registered services
        try await serviceRegistry.startAllServices()

        // Initialize network transport if networking is enabled
        if supportsNetworking {
            try await initializeNetworkTransport()
        }

        // Set the node as running
        _running = true

        logger.info("Node is now running")
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
        logger.info("Node stopped")

        // Stop all registered services
        await serviceRegistry.stopAllServices()

        // Shutdown network transport
        _networkTransport = nil

        // Set the node as not running
        _running = false

        logger.info("Node has been stopped")
    }

    // MARK: - Private Helper Methods

    /// Initialize network transport for remote communication
    private func initializeNetworkTransport() async throws {
        logger.info("Starting networking components...")
        
        guard supportsNetworking else {
            logger.info("Networking is disabled, skipping network initialization")
            return
        }
        
        guard let networkConfig = config.networkConfig else {
            throw NodeError.invalidConfiguration("Network configuration is required")
        }
        
        logger.info("Network config: \(networkConfig)")
        
        // Update local node info
        let localNodeInfo = getLocalNodeInfo()
        // Note: In a real implementation, this would update the stored localNodeInfo
        
        // Initialize the network transport
        if _networkTransport == nil {
            logger.info("Initializing network transport...")
            
            // Create network transport using the factory pattern based on transport_type
            let transport = try await createTransport(networkConfig: networkConfig)
            
            try await transport.start()
            
            // Store the transport
            _networkTransport = transport
        }
        
        // Initialize discovery if enabled
        if let discoveryOptions = networkConfig.discoveryOptions {
            logger.info("Initializing node discovery providers...")
            
            // Check if any providers are configured
            if networkConfig.discoveryProviders.isEmpty {
                throw NodeError.invalidConfiguration("No discovery providers configured")
            }
            
            var discoveryProviders: [NodeDiscovery] = []
            
            // Iterate through all discovery providers and initialize each one
            for providerConfig in networkConfig.discoveryProviders {
                logger.info("Creating discovery provider: \(providerConfig)")
                
                // Create discovery provider instance
                let discoveryProvider = try await createDiscoveryProvider(
                    providerConfig: providerConfig,
                    discoveryOptions: discoveryOptions
                )
                
                // Start announcing on this provider
                logger.info("Starting to announce on discovery provider")
                try await discoveryProvider.start()
                
                discoveryProviders.append(discoveryProvider)
            }
            
            // Store the discovery providers
            _networkDiscoveryProviders = discoveryProviders
        }
        
        logger.info("Networking components started successfully")
    }
    
    /// Create network transport based on configuration
    private func createTransport(networkConfig: NetworkConfig) async throws -> NodeTransport {
        // This would create the actual transport based on networkConfig.transportType
        // For now, return a placeholder that conforms to NodeTransport
        return PlaceholderTransport()
    }
    
    /// Create discovery provider based on configuration
    private func createDiscoveryProvider(
        providerConfig: DiscoveryProviderConfig,
        discoveryOptions: DiscoveryOptions
    ) async throws -> NodeDiscovery {
        // This would create the actual discovery provider
        // For now, return a placeholder that conforms to NodeDiscovery
        return PlaceholderDiscovery()
    }
    
    /// Get local node information
    private func getLocalNodeInfo() -> NodeInfo {
        return localNodeInfo
    }

    /// Compact ID generation from public key
    private func compactId(_ publicKey: Data) -> String {
        // Generate a compact ID from the public key
        // This should match the Rust implementation
        publicKey.prefix(8).map { String(format: "%02x", $0) }.joined()
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

    public func subscribe(topic: String, options: EventRegistrationOptions?, callback: @escaping EventHandler) async throws -> String {
        try await serviceRegistry.subscribe(topic: topic, options: options, callback: callback)
    }

    public func publish(topic: String, data: AnyValue?) async throws {
        await serviceRegistry.publish(topic: topic, data: data, networkId: networkId)
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
        }
    }
}
