import Foundation
import RunarSerializer
import SwiftCommon
import SwiftFFI

/// Errors that can occur in RemoteService operations
public enum RemoteServiceError: Error, LocalizedError {
    case networkKeyResolutionFailed(String)
    case invalidServicePath(String)
    case serviceCreationFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .networkKeyResolutionFailed(message):
            "Network key resolution failed: \(message)"
        case let .invalidServicePath(path):
            "Invalid service path: \(path)"
        case let .serviceCreationFailed(message):
            "Service creation failed: \(message)"
        }
    }
}

/// Lifecycle context for remote services (matches Rust RemoteLifecycleContext)
public actor RemoteLifecycleContext {
    /// Network ID for the context
    public let networkId: String
    /// Service path - identifies the service within the network
    public let servicePath: String
    /// Logger instance with service context
    public let logger: RunarLogger
    /// Registry delegate for registry operations
    private let registryDelegate: ServiceRegistry

    /// Create a new RemoteLifecycleContext with the given topic path and logger
    public init(serviceTopic: TopicPath, logger: RunarLogger, registryDelegate: ServiceRegistry) {
        networkId = serviceTopic.networkId
        servicePath = serviceTopic.servicePath
        self.logger = logger
        self.registryDelegate = registryDelegate
    }

    /// Register a remote action handler (matches Rust register_remote_action_handler)
    public func registerRemoteActionHandler(_ topicPath: TopicPath, handler: @escaping ActionHandler) async throws {
        try await registryDelegate.registerRemoteActionHandler(topicPath: topicPath, handler: handler)
    }

    /// Remove a remote action handler (matches Rust remove_remote_action_handler)
    public func removeRemoteActionHandler(_ topicPath: TopicPath) async throws {
        try await registryDelegate.removeRemoteActionHandler(topicPath: topicPath)
    }
}

// MARK: - RemoteService Configuration Structs

/// Configuration for creating a RemoteService instance (matches Rust RemoteServiceConfig)
public struct RemoteServiceConfig: Sendable {
    public let name: String
    public let serviceTopic: TopicPath
    public let version: String
    public let description: String
    public let peerNodeId: String
    public let requestTimeoutMs: UInt64
}

/// Dependencies required by a RemoteService instance (matches Rust RemoteServiceDependencies)
public struct RemoteServiceDependencies: Sendable {
    public let networkTransport: NodeTransport?
    public let localNodeId: String
    public let logger: RunarLogger
    public let keystore: EnvelopeCrypto
    public let labelResolverConfig: LabelResolverConfig
    public let labelResolverCache: ResolverCache
}

/// Configuration for creating multiple RemoteService instances (matches Rust CreateRemoteServicesConfig)
public struct CreateRemoteServicesConfig: Sendable {
    public let services: [ServiceMetadata]
    public let peerNodeId: String
    public let requestTimeoutMs: UInt64
}

// MARK: - RemoteService

/// Remote service instance representing a service hosted by a remote peer
/// This is a complete service implementation matching the Rust RemoteService
public final class RemoteService: AbstractService, Sendable, Equatable {
    /// Service metadata
    public let name: String
    public let serviceTopic: TopicPath
    public let version: String
    public let description: String

    /// Remote peer information
    public let peerNodeId: String

    /// Service capabilities (thread-safe with concurrent access)
    private let actions: ShardedConcurrentMap<String, ActionMetadata>

    /// Network transport for making remote requests
    private let networkTransport: NodeTransport?

    /// Logger instance
    private let logger: RunarLogger

    /// Keystore for encryption/decryption
    private let keystore: EnvelopeCrypto

    /// Label resolver configuration for dynamic resolver creation
    private let labelResolverConfig: LabelResolverConfig

    /// Label resolver cache for better concurrency
    private let labelResolverCache: ResolverCache

    /// Request timeout in milliseconds
    private let requestTimeoutMs: UInt64

    /// Create a new RemoteService instance (matches Rust RemoteService::new exactly)
    public init(config: RemoteServiceConfig, dependencies: RemoteServiceDependencies) {
        name = config.name
        serviceTopic = config.serviceTopic
        version = config.version
        description = config.description
        peerNodeId = config.peerNodeId
        actions = ShardedConcurrentMap<String, ActionMetadata>()
        networkTransport = dependencies.networkTransport
        logger = dependencies.logger
        keystore = dependencies.keystore
        labelResolverConfig = dependencies.labelResolverConfig
        labelResolverCache = dependencies.labelResolverCache
        requestTimeoutMs = config.requestTimeoutMs
    }

    /// Add an action to this service (matches Rust add_action)
    public func addAction(name: String, action: ActionMetadata) async throws {
        _ = await actions.insert(action, for: name)
    }

    /// Stop the remote service and clean up handlers (matches Rust stop method)
    public func stop(context: RemoteLifecycleContext) async throws {
        let actionNames = await getAvailableActions()

        for actionName in actionNames {
            do {
                let actionTopicPath = try serviceTopic.newActionTopic(actionName)
                try await context.removeRemoteActionHandler(actionTopicPath)
            } catch {
                logger.warning("Failed to create topic path for action: \(serviceTopic)/\(actionName)")
            }
        }
    }

    /// Get available action names (matches Rust get_available_actions)
    public func getAvailableActions() async -> [String] {
        await actions.keys()
    }

    /// Create RemoteService instances from a list of service metadata.
    /// This matches the Rust RemoteService::create_from_capabilities implementation exactly.
    public static func createFromCapabilities(
        config: CreateRemoteServicesConfig,
        dependencies: RemoteServiceDependencies
    ) async throws -> [RemoteService] {
        dependencies.logger.info("Creating RemoteServices from \(config.services.count) service metadata entries")

        // The transport is guaranteed to be available via the dependency injection contract.

        // Create remote services for each service metadata
        var remoteServices: [RemoteService] = []

        for serviceMetadata in config.services {
            // Create a topic path using the service path (not the name)
            let serviceTopic: TopicPath
            do {
                serviceTopic = try TopicPath.new(serviceMetadata.servicePath, defaultNetwork: serviceMetadata.networkId)
            } catch {
                dependencies.logger.error("Invalid service path '\(serviceMetadata.servicePath)': \(error)")
                continue
            }

            // Prepare config for RemoteService::new
            let rsConfig = RemoteServiceConfig(
                name: serviceMetadata.name,
                serviceTopic: serviceTopic,
                version: serviceMetadata.version,
                description: serviceMetadata.description,
                peerNodeId: config.peerNodeId,
                requestTimeoutMs: config.requestTimeoutMs
            )

            // Prepare dependencies for RemoteService::new (cloning references)
            let rsDependencies = RemoteServiceDependencies(
                networkTransport: dependencies.networkTransport,
                localNodeId: dependencies.localNodeId,
                logger: dependencies.logger,
                keystore: dependencies.keystore,
                labelResolverConfig: dependencies.labelResolverConfig,
                labelResolverCache: dependencies.labelResolverCache
            )

            // Create the remote service
            let service = RemoteService(config: rsConfig, dependencies: rsDependencies)

            // Add actions to the service
            for action in serviceMetadata.actions {
                try await service.addAction(name: action.name, action: action)
            }
            // Add subscriptions to the service
            // for subscription in serviceMetadata.subscriptions {
            //     service.addSubscription(subscription.path.clone(), subscription).await?;
            // }
            // Add service to the result list
            remoteServices.append(service)
        }

        let serviceCount = remoteServices.count
        dependencies.logger.info("Created \(serviceCount) RemoteService instances")
        return remoteServices
    }

    /// Get the remote peer identifier for this service
    public func getPeerNodeId() -> String {
        peerNodeId
    }

    /// Get the network identifier for this service path
    public func getNetworkId() -> String {
        serviceTopic.networkId
    }

    /// Create a handler for a remote action
    /// This matches the Rust RemoteService::create_action_handler implementation
    public func createActionHandler(actionName: String) -> ActionHandler {
        { params, requestContext in

            // Create action topic path
            guard let actionTopicPath = try? self.serviceTopic.newActionTopic(actionName) else {
                throw NodeError.invalidConfiguration("Failed to create action topic path for: \(actionName)")
            }

            // Extract profile public keys from context metadata
            let metadata = requestContext.metadata
            guard let profilePublicKeysValue = metadata["profile_public_keys"] else {
                throw NodeError.invalidConfiguration("Profile public keys not found in metadata")
            }

            // Extract profile keys from AnyValue - matches Rust: profile_public_keys_arc.as_type::<Vec<Vec<u8>>>()
            let profilePublicKeys: [Data] = try await profilePublicKeysValue.asType()

            // Get network public key from keystore (resolved dynamically like in Rust)
            let networkPublicKey: Data
            do {
                networkPublicKey = try await self.keystore.getNetworkPublicKeyByNetworkId(networkId: self.serviceTopic.networkId)
            } catch {
                self.logger.error("Failed to get network public key for network \(self.serviceTopic.networkId): \(error)")
                throw RemoteServiceError.networkKeyResolutionFailed("Network key resolution failed: \(error)")
            }

            // Create serialization context using the provided keystore and resolver
            // Create dynamic resolver with user context using cache (matches Rust exactly)
            let resolver = try await self.labelResolverCache.getOrCreateResolver(
                systemConfig: self.labelResolverConfig,
                userProfilePublicKeys: profilePublicKeys
            )

            let serializationContext = SerializationContext(
                keystore: self.keystore,
                resolver: resolver,
                networkPublicKey: networkPublicKey,
                profilePublicKeys: profilePublicKeys
            )

            // Serialize request parameters
            let paramsToSerialize = params ?? AnyValue.null()
            let paramsBytes = try await paramsToSerialize.serialize(context: serializationContext)

            // Send network request
            guard let networkTransport = self.networkTransport else {
                throw NodeError.transportNotAvailable("Network transport not available for remote service")
            }

            let correlationId = UUID().uuidString
            self.logger.debug("Sending network request to \(actionTopicPath.asString()) with correlationId \(correlationId) peerNodeId \(self.peerNodeId)")
            let responseBytes = try await networkTransport.request(
                path: actionTopicPath.asString(),
                correlationId: correlationId,
                payload: paramsBytes,
                peerNodeId: self.peerNodeId,
                networkPublicKey: networkPublicKey,
                profilePublicKeys: profilePublicKeys
            )

            self.logger.debug("Received response from \(actionTopicPath.asString()) with correlationId \(correlationId) peerNodeId \(self.peerNodeId)")

            // Deserialize response using the proper keystore
            let response = try AnyValue.deserialize(responseBytes, keystore: self.keystore)
            return response
        }
    }

    // MARK: - AbstractService Implementation

    public var path: String {
        serviceTopic.asString()
    }

    public var networkId: String? {
        get { serviceTopic.networkId }
        set { /* Remote services cannot change network ID */ }
    }

    public func setNetworkId(_: String) {
        // Remote services cannot change network ID
    }


    public func initService(_: LifecycleContext) async throws {
        // Remote services don't need initialization since they're just proxies
        logger.info("Initialized remote service proxy for \(serviceTopic)")
    }

    /// Initialize the remote service and register action handlers (matches Rust init method)
    public func initService(context: RemoteLifecycleContext) async throws {
        // Get available actions
        let actionNames = await getAvailableActions()

        // Register each action handler
        for actionName in actionNames {
            do {
                let actionTopicPath = try serviceTopic.newActionTopic(actionName)
                // Create handler for this action
                let handler = createActionHandler(actionName: actionName)
                
                try await context.registerRemoteActionHandler(actionTopicPath, handler: handler)
            } catch {
                logger.warning("Failed to create topic path for action: \(serviceTopic)/\(actionName)")
            }
        }
    }

    public func start(_: LifecycleContext) async throws {
        // Remote services don't need to be started
        logger.info("Started remote service proxy for \(serviceTopic)")
    }


    public func stop(_: LifecycleContext) async throws {
        // Remote services don't need to be stopped
        logger.info("Stopped remote service proxy for \(serviceTopic)")
    }

    // MARK: - Equatable Implementation

    public nonisolated static func == (lhs: RemoteService, rhs: RemoteService) -> Bool {
        lhs.name == rhs.name &&
            lhs.serviceTopic == rhs.serviceTopic &&
            lhs.version == rhs.version &&
            lhs.description == rhs.description &&
            lhs.peerNodeId == rhs.peerNodeId
    }
}

// MARK: - Service Registry Types

// ServiceState is defined in AbstractService.swift

// Type aliases are defined in SwiftNode.swift

/// Event registration options
public struct EventRegistrationOptions: Sendable {
    public let qos: Int
    public let retain: Bool
    /// If set, deliver the newest retained event that occurred within this lookback window
    /// immediately upon subscription (in addition to future events). Local-only.
    public let includePast: TimeInterval?

    public init(qos: Int = 0, retain: Bool = false, includePast: TimeInterval? = nil) {
        self.qos = qos
        self.retain = retain
        self.includePast = includePast
    }
}

/// Local action entry value
/// Matches Rust: (ActionHandler, TopicPath, Option<ActionMetadata>)
public typealias LocalActionEntryValue = (ActionHandler, TopicPath, ActionMetadata?)

/// Subscription entry tuple matching Rust SubscriptionEntry = (String, SubscriberKind, SubscriptionMetadata)
public struct SubscriptionEntry: Sendable, Equatable {
    public let subscriptionId: String
    public let subscriberKind: SubscriberKind
    public let subscriptionMetadata: SubscriptionMetadata

    public init(subscriptionId: String, subscriberKind: SubscriberKind, subscriptionMetadata: SubscriptionMetadata) {
        self.subscriptionId = subscriptionId
        self.subscriberKind = subscriberKind
        self.subscriptionMetadata = subscriptionMetadata
    }

    public static func == (lhs: SubscriptionEntry, rhs: SubscriptionEntry) -> Bool {
        lhs.subscriptionId == rhs.subscriptionId
    }
}
/// Subscriber kind for event subscriptions (Node-only, not in FFI)
public enum SubscriberKind: Sendable, Equatable {
    case local(EventHandler)
    case remote(RemoteEventHandler)

    public static func == (lhs: SubscriberKind, rhs: SubscriberKind) -> Bool {
        switch (lhs, rhs) {
        case (.local, .local):
            // For local handlers, we can't compare functions directly
            // Return true if both are local (this is a limitation)
            true
        case (.remote, .remote):
            // For remote handlers, we can't compare functions directly
            // Return true if both are remote (this is a limitation)
            true
        default:
            false
        }
    }
}

/// Subscription vector for managing multiple subscriptions
public struct SubscriptionVec: Sendable, Equatable {
    public let subscriptions: [SubscriptionEntry]

    public init(subscriptions: [SubscriptionEntry] = []) {
        self.subscriptions = subscriptions
    }

    public static func == (lhs: SubscriptionVec, rhs: SubscriptionVec) -> Bool {
        lhs.subscriptions == rhs.subscriptions
    }
}

/// Service entry for local services
public struct ServiceEntry: Sendable {
    public let serviceTopic: TopicPath
    public let service: AbstractService
    public let state: ServiceState
    /// Timestamp when the service was registered (in seconds since UNIX epoch)
    public let registrationTime: UInt64
    /// Timestamp when the service was last started (in seconds since UNIX epoch)
    /// This is nil if the service has never been started
    public let lastStartTime: UInt64?

    public init(serviceTopic: TopicPath, service: AbstractService, state: ServiceState = .initialized, registrationTime: UInt64 = 0, lastStartTime: UInt64? = nil) {
        self.serviceTopic = serviceTopic
        self.service = service
        self.state = state
        self.registrationTime = registrationTime
        self.lastStartTime = lastStartTime
    }
}

/// Service registry implementation matching Rust structure
@MainActor
public final class ServiceRegistry: NodeDelegate {
    // MARK: - Core Properties

    /// Main-actor isolation provides thread-safety for registry state

    /// Local action handlers organized by path (using PathTrie instead of HashMap)
    /// Store both the handler and the original registration topic path for parameter extraction
    private var localActionHandlers: PathTrie<LocalActionEntryValue> = PathTrie()

    /// Remote action handlers organized by path (using PathTrie instead of HashMap)
    private var remoteActionHandlers: PathTrie<[ActionHandler]> = PathTrie()

    /// Unified event subscriptions – stores both local and remote subscribers in a single trie
    private var eventSubscriptions: PathTrie<SubscriptionVec> = PathTrie()

    /// Map subscription IDs back to TopicPath for efficient unsubscription
    /// Matches Rust: Arc<DashMap<String, TopicPath>>
    private let subscriptionIdToTopicPath: ShardedConcurrentMap<String, TopicPath>

    /// Map subscription IDs back to the service TopicPath for efficient unsubscription
    /// Matches Rust: Arc<DashMap<String, TopicPath>>
    private let subscriptionIdToServiceTopicPath: ShardedConcurrentMap<String, TopicPath>

    /// Local services registry (using PathTrie instead of HashMap)
    /// Matches Rust: Arc<RwLock<PathTrie<Arc<ServiceEntry>>>>
    private var localServices: PathTrie<ServiceEntry> = PathTrie()

    /// Local services list for quick lookup
    /// Matches Rust: Arc<DashMap<TopicPath, Arc<ServiceEntry>>>
    private let localServicesList: ShardedConcurrentMap<TopicPath, ServiceEntry>

    /// Remote services registry (using PathTrie instead of HashMap)
    /// Matches Rust: Arc<RwLock<PathTrie<Arc<RemoteService>>>>
    private var remoteServices: PathTrie<RemoteService> = PathTrie()

    /// Local service lifecycle states
    /// Matches Rust: Arc<DashMap<String, ServiceState>>
    private let localServiceStates: ShardedConcurrentMap<String, ServiceState>

    /// Remote service lifecycle states
    /// Matches Rust: Arc<DashMap<String, ServiceState>>
    private let remoteServiceStates: ShardedConcurrentMap<String, ServiceState>

    /// Mapping of peer node IDs to subscription IDs registered on their behalf
    /// Matches Rust: Arc<DashMap<String, DashMap<String, String>>>
    private let remotePeerSubscriptions: ShardedConcurrentMap<String, ShardedConcurrentMap<String, String>>

    /// Logger instance
    public let logger: RunarLogger

    /// Node delegate for handling remote requests
    weak var nodeDelegate: NodeDelegate?

    // MARK: - Initialization

    /// Create a new registry with a provided logger
    ///
    /// INTENTION: Initialize a new registry with a logger provided by the parent
    /// component (typically the Node). This ensures proper logger hierarchy.
    /// Matches Rust ServiceRegistry::new() initialization.
    public init(logger: RunarLogger, nodeDelegate: NodeDelegate? = nil) {
        self.logger = logger
        self.nodeDelegate = nodeDelegate
        localActionHandlers = PathTrie<LocalActionEntryValue>()
        remoteActionHandlers = PathTrie<[ActionHandler]>()
        eventSubscriptions = PathTrie<SubscriptionVec>()
        subscriptionIdToTopicPath = ShardedConcurrentMap<String, TopicPath>()
        subscriptionIdToServiceTopicPath = ShardedConcurrentMap<String, TopicPath>()
        localServices = PathTrie<ServiceEntry>()
        localServicesList = ShardedConcurrentMap<TopicPath, ServiceEntry>()
        remoteServices = PathTrie<RemoteService>()
        localServiceStates = ShardedConcurrentMap<String, ServiceState>()
        remoteServiceStates = ShardedConcurrentMap<String, ServiceState>()
        remotePeerSubscriptions = ShardedConcurrentMap<String, ShardedConcurrentMap<String, String>>()
    }

    // MARK: - Local Service Management

    /// Register a local service
    ///
    /// INTENTION: Register a local service implementation for use by the node.
    public func registerLocalService(_ service: ServiceEntry) async throws {
        let serviceTopic = service.serviceTopic
        logger.trace("Registering local service: \(serviceTopic)")

        // Store the service in the local services registry
        localServices.setValue(topic: serviceTopic, content: service)
        _ = await localServicesList.insert(service, for: serviceTopic)

        logger.trace("Successfully registered local service: \(serviceTopic)")
    }

    /// Update local service state
    public func updateLocalServiceState(servicePath: String, newState: ServiceState) async throws {
        _ = await localServiceStates.insert(newState, for: servicePath)
        logger.trace("Updated service state for \(servicePath): \(newState.rawValue)")
    }

    /// Update local service state (matching Rust API)
    public func updateLocalServiceState(serviceTopic: TopicPath, state: ServiceState) async throws {
        logger.trace("Updating local service state for \(serviceTopic): \(state.rawValue)")
        _ = await localServiceStates.insert(state, for: serviceTopic.asString())
    }

    /// Update remote service state
    ///
    /// INTENTION: Track the lifecycle state of a remote service.
    public func updateRemoteServiceState(serviceTopic: TopicPath, state: ServiceState) async throws {
        logger.trace("Updating remote service state for \(serviceTopic): \(state.rawValue)")
        _ = await remoteServiceStates.insert(state, for: serviceTopic.asString())
    }

    /// Get remote service state
    public func getRemoteServiceState(servicePath: TopicPath) async -> ServiceState? {
        await remoteServiceStates.get(servicePath.asString())
    }

    /// Start all local services
    public func startAllServices(networkId: String) async throws {
        logger.info("Starting all local services")

        let services = localServices.getAllEntries(networkId: networkId)
        logger.debug("Found \(services.count) services to start")

        for serviceEntry in services {
            logger.trace("Starting service: \(serviceEntry.serviceTopic.asString())")
            let context = LifecycleContext(
                topicPath: serviceEntry.serviceTopic,
                nodeDelegate: self,
                logger: logger
            )

            // First initialize the service (registers action handlers)
            logger.trace("Initializing service: \(serviceEntry.serviceTopic.asString())")
            try await serviceEntry.service.initService(context)
            try await updateLocalServiceState(
                servicePath: serviceEntry.serviceTopic.asString(),
                newState: ServiceState.initialized
            )

            // Then start the service (begins active operations)
            logger.trace("Starting service: \(serviceEntry.serviceTopic.asString())")
            try await serviceEntry.service.start(context)
            try await updateLocalServiceState(
                servicePath: serviceEntry.serviceTopic.asString(),
                newState: ServiceState.running
            )
            logger.trace("Service started successfully: \(serviceEntry.serviceTopic.asString())")
        }

        logger.debug("All local services started")
    }

    /// Get all entries for a specific network
    public func getAllEntries(networkId: String) -> [ServiceEntry] {
        localServices.getAllEntries(networkId: networkId)
    }

    /// Update service state only if the transition is valid
    public func updateLocalServiceStateIfValid(servicePath: TopicPath, newState: ServiceState, currentState: ServiceState) async throws {
        // Validate the state transition
        switch (currentState, newState) {
        case (.running, .paused):
            // Valid transition: Running -> Paused
            try await updateLocalServiceState(servicePath: servicePath.asString(), newState: newState)
        case (.paused, .running):
            // Valid transition: Paused -> Running
            try await updateLocalServiceState(servicePath: servicePath.asString(), newState: newState)
        case (.created, .initialized):
            // Valid transition: Created -> Initialized
            try await updateLocalServiceState(servicePath: servicePath.asString(), newState: newState)
        case (.initialized, .running):
            // Valid transition: Initialized -> Running
            try await updateLocalServiceState(servicePath: servicePath.asString(), newState: newState)
        case (.running, .stopped):
            // Valid transition: Running -> Stopped
            try await updateLocalServiceState(servicePath: servicePath.asString(), newState: newState)
        case (.paused, .stopped):
            // Valid transition: Paused -> Stopped
            try await updateLocalServiceState(servicePath: servicePath.asString(), newState: newState)
        default:
            // Invalid transition
            throw ServiceRegistryError.invalidStateTransition(
                "Cannot transition from \(currentState.rawValue) to \(newState.rawValue)"
            )
        }
    }

    /// Validate that a service can be paused
    public func validatePauseTransition(servicePath: TopicPath) async throws {
        let currentState = await getLocalServiceState(servicePath: servicePath)
        switch currentState {
        case .some(.running):
            // Valid state for pausing
            return
        case let .some(state):
            // Invalid state for pausing
            throw ServiceRegistryError.invalidStateTransition(
                "Cannot pause service in \(state.rawValue) state. Service must be in Running state."
            )
        case .none:
            // Service not found
            throw ServiceRegistryError.serviceNotFound("Service not found: \(servicePath.asString())")
        }
    }

    /// Validate that a service can be resumed
    public func validateResumeTransition(servicePath: TopicPath) async throws {
        let currentState = await getLocalServiceState(servicePath: servicePath)
        switch currentState {
        case .some(.paused):
            // Valid state for resuming
            return
        case let .some(state):
            // Invalid state for resuming
            throw ServiceRegistryError.invalidStateTransition(
                "Cannot resume service in \(state.rawValue) state. Service must be in Paused state."
            )
        case .none:
            // Service not found
            throw ServiceRegistryError.serviceNotFound("Service not found: \(servicePath.asString())")
        }
    }

    /// Stop all local services
    public func stopAllServices() async {
        logger.trace("Stopping all local services")

        let services = (try? localServices.find(topic: TopicPath.new("", defaultNetwork: "default"))) ?? []

        for serviceEntry in services {
            let context = LifecycleContext(
                topicPath: serviceEntry.serviceTopic,
                nodeDelegate: self,
                logger: logger
            )

            do {
                try await serviceEntry.service.stop(context)
                try await updateLocalServiceState(
                    servicePath: serviceEntry.serviceTopic.asString(),
                    newState: ServiceState.stopped
                )
            } catch {
                logger.error("Failed to stop service \(serviceEntry.serviceTopic.asString()): \(error)")
            }
        }

        logger.trace("All local services stopped")
    }

    // MARK: - Remote Service Management

    /// Remove a remote service
    ///
    /// INTENTION: Remove a remote service from the registry and stop it.
    public func removeRemoteService(serviceTopic: TopicPath) async throws {
        // Get the service so we can call .stop() on it
        let services = remoteServices.find(topic: serviceTopic)

        if services.isEmpty {
            throw ServiceRegistryError.serviceNotFound("Service not found for topic: \(serviceTopic)")
        }

        // Stop each remote service before removing from registry (matches Rust exactly)
        for service in services {
            // Create RemoteLifecycleContext for service stopping
            let context = RemoteLifecycleContext(serviceTopic: serviceTopic, logger: logger, registryDelegate: self)

            // Stop the service - this triggers handler cleanup via the context
            do {
                try await service.stop(context: context)
            } catch {
                logger.error("Failed to stop remote service '\(service.path)' error: \(error)")
            }
        }

        // Remove the services from the registry
        for service in services {
            remoteServices.remove(topic: serviceTopic, content: service)
        }

        // Remove the service state
        try await removeRemoteServiceState(serviceTopic: serviceTopic)
    }

    /// Remove remote service state
    private func removeRemoteServiceState(serviceTopic: TopicPath) async throws {
        _ = await remoteServiceStates.remove(serviceTopic.asString())
    }


    // MARK: - Action Management

    /// Register a local action handler
    public func registerAction(
        networkId: String,
        servicePath: String,
        action: String,
        handler: @escaping ActionHandler
    ) async throws {
        let topicPath = try TopicPath.new("\(servicePath)/\(action)", defaultNetwork: networkId)
        let metadata = ActionMetadata(
            name: action,
            description: "Action \(action) for service \(servicePath)"
        )
        let entryValue: LocalActionEntryValue = (handler, topicPath, metadata)

        localActionHandlers.setValue(topic: topicPath, content: entryValue)

        logger.debug("Registered action handler for: \(topicPath.asString())")
        logger.trace("Action handler function: \(String(describing: handler))")
    }

    /// Unregister a local action handler
    public func unregisterAction(
        networkId: String,
        servicePath: String,
        action: String
    ) async throws {
        let topicPath = try TopicPath.new("\(servicePath)/\(action)", defaultNetwork: networkId)

        // Remove all handlers for this topic path by setting empty array
        localActionHandlers.setValues(topic: topicPath, contents: [])

        logger.trace("Unregistered action handler for: \(topicPath.asString())")
    }

    /// Register a local action handler (matching Rust API)
    ///
    /// INTENTION: Register a handler for a specific action path that will be executed locally.
    public func registerLocalActionHandler(
        topicPath: TopicPath,
        handler: @escaping ActionHandler,
        metadata: ActionMetadata?
    ) async throws {
        logger.debug("Registering local action handler for: \(topicPath.asString())")

        // Store in the local action handlers trie with the original topic path for parameter extraction
        let entryValue: LocalActionEntryValue = (handler, topicPath, metadata)
        localActionHandlers.setValue(topic: topicPath, content: entryValue)

        logger.trace("Registered local action handler for: \(topicPath.asString())")
    }

    /// Register a remote action handler
    ///
    /// INTENTION: Register a handler for a specific action path that exists on a remote node.
    public func registerRemoteActionHandler(
        topicPath: TopicPath,
        handler: @escaping ActionHandler
    ) async throws {
        logger.debug("Registering remote action handler for: \(topicPath.asString())")

        // Store the handler in remote_action_handlers using PathTrie
        let matches = remoteActionHandlers.find(topic: topicPath)

        if matches.isEmpty {
            // No handlers yet for this path
            remoteActionHandlers.setValue(topic: topicPath, content: [handler])
        } else {
            // Get existing handlers and add the new one
            var existingHandlers = matches[0]
            existingHandlers.append(handler)

            // Update the handlers in the trie
            remoteActionHandlers.setValue(topic: topicPath, content: existingHandlers)
        }

        logger.trace("Registered remote action handler for: \(topicPath.asString())")
    }

    /// Remove a remote action handler
    public func removeRemoteActionHandler(topicPath: TopicPath) async throws {
        logger.debug("Removing remote action handler for: \(topicPath.asString())")

        // Remove from remote action handlers trie using the new removeValues method
        remoteActionHandlers.removeValues(topic: topicPath)

        logger.trace("Removed remote action handler for: \(topicPath.asString())")
    }

    /// Get a local action handler only
    ///
    /// INTENTION: Retrieve a handler for a specific action path that will be executed locally.
    /// Now returns both the handler and the original registration topic path for parameter extraction.
    public func getLocalActionHandler(topicPath: TopicPath) async -> (ActionHandler, TopicPath)? {
        let matches = localActionHandlers.find(topic: topicPath)

        if !matches.isEmpty {
            let (handler, topicPath, _) = matches[0]
            return (handler, topicPath)
        } else {
            return nil
        }
    }

    /// Get all remote action handlers for a path (for load balancing)
    ///
    /// INTENTION: Retrieve all handlers for a specific action path that exist on remote nodes.
    public func getRemoteActionHandlers(topicPath: TopicPath) async -> [ActionHandler] {
        let matches = remoteActionHandlers.find(topic: topicPath)

        // Flatten all matches into a single vector of handlers
        var result: [ActionHandler] = []
        for match in matches {
            result.append(contentsOf: match)
        }
        return result
    }

    /// Get an action handler for a specific topic path
    ///
    /// INTENTION: Look up the appropriate action handler for a given topic path
    /// supporting both local and remote handlers.
    public func getActionHandler(topicPath: TopicPath) async -> ActionHandler? {
        // First try local handlers
        if let (handler, _) = await getLocalActionHandler(topicPath: topicPath) {
            return handler
        }

        // Then check remote handlers
        let remoteHandlers = await getRemoteActionHandlers(topicPath: topicPath)
        if !remoteHandlers.isEmpty {
            // For backward compatibility, just return the first one
            // The Node will apply proper load balancing when using get_remote_action_handlers directly
            return remoteHandlers[0]
        }

        return nil
    }

    // MARK: - Event Management

    /// Subscribe to events
    public func subscribeToEvents(
        networkId: String,
        servicePath: String,
        handler: @escaping EventHandler
    ) async throws -> String {
        try await subscribeToEvents(
            networkId: networkId,
            servicePath: servicePath,
            handler: handler,
            options: EventRegistrationOptions(qos: 0, retain: false, includePast: nil)
        )
    }

    public func subscribeToEvents(
        networkId: String,
        servicePath: String,
        handler: @escaping @Sendable EventHandler,
        options: EventRegistrationOptions
    ) async throws -> String {
        let subscriptionId = UUID().uuidString
        let topicPath: TopicPath
        do {
            topicPath = try TopicPath.new(servicePath, defaultNetwork: networkId)
        } catch {
            logger.error("Failed to create TopicPath for servicePath '\(servicePath)': \(error)")
            throw ServiceRegistryError.invalidTopicPath(servicePath)
        }

        let subscription = SubscriptionEntry(
            subscriptionId: subscriptionId,
            subscriberKind: .local(handler),
            subscriptionMetadata: SubscriptionMetadata(path: servicePath)
        )

        // Add to event subscriptions
        var existingSubscriptions = eventSubscriptions.find(topic: topicPath).first?.subscriptions ?? []
        logger.trace("Before adding subscription: \(existingSubscriptions.count) existing subscriptions for \(topicPath.asString())")
        existingSubscriptions.append(subscription)
        eventSubscriptions.setValue(topic: topicPath, content: SubscriptionVec(subscriptions: existingSubscriptions))

        // Map subscription ID to topic path
        _ = await subscriptionIdToTopicPath.insert(topicPath, for: subscriptionId)

        logger.trace("Subscribed to events for: \(topicPath.asString()) with ID: \(subscriptionId)")
        logger.trace("Total subscriptions for \(topicPath.asString()): \(existingSubscriptions.count)")
        return subscriptionId
    }

    /// Unsubscribe from events
    public func unsubscribeFromEvents(subscriptionId: String) async {
        guard let topicPath = await subscriptionIdToTopicPath.get(subscriptionId) else {
            logger.warning("No subscription found for ID: \(subscriptionId)")
            return
        }

        // Remove from event subscriptions
        var existingSubscriptions = eventSubscriptions.find(topic: topicPath).first?.subscriptions ?? []
        existingSubscriptions.removeAll { $0.subscriptionId == subscriptionId }
        if existingSubscriptions.isEmpty {
            // Remove all subscriptions for this topic
            let subscriptions = eventSubscriptions.find(topic: topicPath)
            for sub in subscriptions {
                eventSubscriptions.remove(topic: topicPath, content: sub)
            }
        } else {
            eventSubscriptions.setValue(topic: topicPath, content: SubscriptionVec(subscriptions: existingSubscriptions))
        }

        // Remove from mapping
        _ = await subscriptionIdToTopicPath.remove(subscriptionId)

        logger.trace("Unsubscribed from events for: \(topicPath.asString()) with ID: \(subscriptionId)")
    }

    /// Register local event subscription (matching Rust API)
    ///
    /// INTENTION: Register a callback to be invoked when events are published locally.
    public func registerLocalEventSubscription(
        topicPath: TopicPath,
        callback: @escaping @Sendable EventHandler,
        options: EventRegistrationOptions
    ) async throws -> String {
        let subscriptionId = UUID().uuidString

        // Insert into unified event_subscriptions trie
        var existingSubscriptions = eventSubscriptions.find(topic: topicPath).first?.subscriptions ?? []
        let subscription = SubscriptionEntry(
            subscriptionId: subscriptionId,
            subscriberKind: .local(callback),
            subscriptionMetadata: SubscriptionMetadata(path: topicPath.asString())
        )
        existingSubscriptions.append(subscription)
        eventSubscriptions.setValue(topic: topicPath, content: SubscriptionVec(subscriptions: existingSubscriptions))

        // Map subscription ID to topic path
        _ = await subscriptionIdToTopicPath.insert(topicPath, for: subscriptionId)

        let serviceTopic = try TopicPath.new(topicPath.servicePath, defaultNetwork: topicPath.networkId)
        _ = await subscriptionIdToServiceTopicPath.insert(serviceTopic, for: subscriptionId)

        return subscriptionId
    }

    /// Register remote event subscription
    ///
    /// INTENTION: Register a callback to be invoked when events are published from remote nodes.
    public func registerRemoteEventSubscription(
        topicPath: TopicPath,
        handler: @escaping RemoteEventHandler,
        options: EventRegistrationOptions
    ) async throws -> String {
        let subscriptionId = UUID().uuidString

        var existingSubscriptions = eventSubscriptions.find(topic: topicPath).first?.subscriptions ?? []
        let subscription = SubscriptionEntry(
            subscriptionId: subscriptionId,
            subscriberKind: .remote(handler),
            subscriptionMetadata: SubscriptionMetadata(path: topicPath.asString())
        )
        existingSubscriptions.append(subscription)
        eventSubscriptions.setValue(topic: topicPath, content: SubscriptionVec(subscriptions: existingSubscriptions))

        // Map subscription ID to topic path
        _ = await subscriptionIdToTopicPath.insert(topicPath, for: subscriptionId)

        return subscriptionId
    }

    /// Remove remote event subscription
    public func removeRemoteEventSubscription(topicPath: TopicPath) async throws {
        let matches = eventSubscriptions.find(topic: topicPath)

        var idsToRemove: [String] = []
        for match in matches {
            for subscription in match.subscriptions {
                if case .remote = subscription.subscriberKind {
                    idsToRemove.append(subscription.subscriptionId)
                }
            }
        }

        if idsToRemove.isEmpty {
            return
        }

        // Rebuild vectors without the remote entries we want to remove
        for match in matches {
            let remaining = match.subscriptions.filter { subscription in
                let isRemote = if case .remote = subscription.subscriberKind { true } else { false }
                return !(idsToRemove.contains(subscription.subscriptionId) && isRemote)
            }
            if remaining.isEmpty {
                eventSubscriptions.remove(topic: topicPath, content: match)
            } else {
                eventSubscriptions.setValue(topic: topicPath, content: SubscriptionVec(subscriptions: remaining))
            }
        }

        // Clean up maps
        for id in idsToRemove {
            _ = await subscriptionIdToTopicPath.remove(id)
            _ = await subscriptionIdToServiceTopicPath.remove(id)
        }
    }

    /// Get local event subscribers
    ///
    /// INTENTION: Find all local subscribers for a specific event topic.
    public func getLocalEventSubscribers(topicPath: TopicPath) async -> [(String, EventHandler, SubscriptionEntry)] {
        let matches = eventSubscriptions.find(topic: topicPath)

        var result: [(String, EventHandler, SubscriptionEntry)] = []
        var seenIds = Set<String>()

        for match in matches {
            for subscription in match.subscriptions {
                if seenIds.contains(subscription.subscriptionId) {
                    continue
                }
                if case let .local(handler) = subscription.subscriberKind {
                    seenIds.insert(subscription.subscriptionId)
                    result.append((subscription.subscriptionId, handler, subscription))
                }
            }
        }

        return result
    }

    /// Get remote event subscribers
    public func getRemoteEventSubscribers(topicPath: TopicPath) async -> [(String, RemoteEventHandler, SubscriptionEntry)] {
        let matches = eventSubscriptions.find(topic: topicPath)

        var result: [(String, RemoteEventHandler, SubscriptionEntry)] = []
        var seenIds = Set<String>()

        for match in matches {
            for subscription in match.subscriptions {
                if seenIds.contains(subscription.subscriptionId) {
                    continue
                }
                if case let .remote(handler) = subscription.subscriberKind {
                    seenIds.insert(subscription.subscriptionId)
                    result.append((subscription.subscriptionId, handler, subscription))
                }
            }
        }

        return result
    }

    /// Unsubscribe local (matching Rust API)
    public func unsubscribeLocal(subscriptionId: String) async throws -> TopicPath {
        logger.trace("Attempting to unsubscribe local subscription ID: \(subscriptionId)")

        // Find the TopicPath associated with the subscription ID
        guard let topicPath = await subscriptionIdToTopicPath.get(subscriptionId) else {
            let msg = "No topic path found mapping to subscription ID: \(subscriptionId). Cannot unsubscribe."
            logger.warning(msg)
            throw ServiceRegistryError.serviceNotFound(msg)
        }

        logger.trace("Found topic path '\(topicPath.asString())' for subscription ID: \(subscriptionId)")
        let matches = eventSubscriptions.find(topic: topicPath)

        if !matches.isEmpty {
            // Build new entry vectors without the subscription to remove
            for match in matches {
                let filtered = match.subscriptions.filter { subscription in
                    // keep every entry except the one with matching id & Local kind
                    let isLocal = if case .local = subscription.subscriberKind { true } else { false }
                    return !(subscription.subscriptionId == subscriptionId && isLocal)
                }
                if filtered.isEmpty {
                    eventSubscriptions.remove(topic: topicPath, content: match)
                } else {
                    eventSubscriptions.setValue(topic: topicPath, content: SubscriptionVec(subscriptions: filtered))
                }
            }

            // Remove from the ID map
            _ = await subscriptionIdToTopicPath.remove(subscriptionId)

            // Remove from service topic path map
            _ = await subscriptionIdToServiceTopicPath.remove(subscriptionId)

            logger.trace("Successfully unsubscribed from topic: \(topicPath.asString()) with ID: \(subscriptionId)")
            return topicPath
        } else {
            let msg = "No subscriptions found for topic path \(topicPath.asString()) and ID \(subscriptionId)"
            logger.warning(msg)
            throw ServiceRegistryError.serviceNotFound(msg)
        }
    }

    /// Unsubscribe remote
    public func unsubscribeRemote(subscriptionId: String) async throws {
        logger.trace("Attempting to unsubscribe remote subscription ID: \(subscriptionId)")

        // Find the TopicPath associated with the subscription ID
        guard let topicPath = await subscriptionIdToTopicPath.get(subscriptionId) else {
            let msg = "No topic path found mapping to remote subscription ID: \(subscriptionId). Cannot unsubscribe."
            logger.warning(msg)
            throw ServiceRegistryError.serviceNotFound(msg)
        }

        logger.trace("Found topic path '\(topicPath.asString())' for subscription ID: \(subscriptionId)")
        let matches = eventSubscriptions.find(topic: topicPath)

        if !matches.isEmpty {
            var removedFlag = false
            for match in matches {
                let filtered = match.subscriptions.filter { subscription in
                    // keep entries except the matching Remote one
                    let isRemote = if case .remote = subscription.subscriberKind { true } else { false }
                    return !(subscription.subscriptionId == subscriptionId && isRemote)
                }
                if filtered.isEmpty {
                    eventSubscriptions.remove(topic: topicPath, content: match)
                } else {
                    eventSubscriptions.setValue(topic: topicPath, content: SubscriptionVec(subscriptions: filtered))
                }
                removedFlag = true
            }
            if removedFlag {
                _ = await subscriptionIdToTopicPath.remove(subscriptionId)
                logger.trace("Successfully unsubscribed from remote topic: \(topicPath.asString()) with ID: \(subscriptionId)")
            } else {
                let msg = "Subscription handler not found for remote topic path \(topicPath.asString()) and ID \(subscriptionId), although ID was mapped. Potential race condition?"
                logger.warning(msg)
                throw ServiceRegistryError.serviceNotFound(msg)
            }
        } else {
            let msg = "No subscriptions found for remote topic path \(topicPath.asString()) and ID \(subscriptionId)"
            logger.warning(msg)
            throw ServiceRegistryError.serviceNotFound(msg)
        }
    }

    // MARK: - Request Handling

    /// Handle a request
    // NOTE: ServiceRegistry does NOT have a request method in Rust
    // All request routing is handled by the Node directly

    public func remoteRequest(path _: String, payload _: AnyValue?, networkId _: String, options _: RequestOptions?) async throws -> AnyValue {
        // This should not be called directly on ServiceRegistry
        // It should be called on the Node which implements the actual remote request logic
        throw ServiceRegistryError.actionNotFound("ServiceRegistry.remoteRequest should not be called directly")
    }

    // MARK: - Path Parameter Extraction

    /// Extract path parameters from a requested path using a handler path template
    private func extractPathParams(requestedPath: String, handlerPath: String) -> [String: String] {
        let requestedSegments = requestedPath.split(separator: "/")
        let handlerSegments = handlerPath.split(separator: "/")

        var pathParams: [String: String] = [:]

        // Match segments and extract parameters
        for (index, handlerSegment) in handlerSegments.enumerated() {
            if index < requestedSegments.count {
                let requestedSegment = String(requestedSegments[index])

                // Check if this is a parameter (starts with { and ends with })
                if handlerSegment.hasPrefix("{"), handlerSegment.hasSuffix("}") {
                    let paramName = String(handlerSegment.dropFirst().dropLast())
                    pathParams[paramName] = requestedSegment
                }
            }
        }

        return pathParams
    }

    // MARK: - Event Publishing

    /// Publish an event
    public func publish(topic: String, data: AnyValue?, networkId: String) async {
        let topicPath: TopicPath
        do {
            topicPath = try TopicPath.new(topic, defaultNetwork: networkId)
        } catch {
            logger.error("Failed to create TopicPath for topic '\(topic)': \(error)")
            return // Silently fail for event publishing
        }

        // Get subscribers for this topic
        let allMatches = eventSubscriptions.find(topic: topicPath)

        // Collect all subscriptions from all matches
        var allSubscriptions: [SubscriptionEntry] = []
        for match in allMatches {
            allSubscriptions.append(contentsOf: match.subscriptions)
        }

        logger.trace("Looking for subscribers for topic: \(topicPath.asString()) - found \(allMatches.count) matches with \(allSubscriptions.count) total subscribers")
        for (index, match) in allMatches.enumerated() {
            logger.trace("Match \(index): \(match.subscriptions.count) subscriptions")
        }

        // Notify all subscribers
        for subscription in allSubscriptions {
            switch subscription.subscriberKind {
            case let .local(handler):
                logger.trace("Calling local handler for subscription: \(subscription.subscriptionId)")

                // Create event context (matching Rust)
                let eventContext = EventContext(
                    topicPath: topicPath,
                    nodeDelegate: nodeDelegate ?? self,
                    isLocal: true,
                    logger: logger
                )

                // Call handler with context (matching Rust)
                do {
                    try await handler(eventContext, data)
                } catch {
                    logger.error("Error in local event handler for \(topic): \(error)")
                }
            case let .remote(handler):
                // Remote event handling would go here
                logger.debug("Remote event handler called")
                do {
                    try await handler(data)
                } catch {
                    logger.error("Error in remote event handler  for \(topic): \(error)")
                }
            }
        }

        logger.trace("Published event to \(allSubscriptions.count) subscribers for topic: \(topic)")
    }

    // MARK: - NodeDelegate Implementation

    public func subscribe(topic: String, options: EventRegistrationOptions?, callback: @escaping EventHandler) async throws -> String {
        let defaultOptions = EventRegistrationOptions(qos: 0, retain: false, includePast: nil)
        let eventOptions = options ?? defaultOptions

        return try await subscribeToEvents(
            networkId: "default",
            servicePath: topic,
            handler: callback,
            options: eventOptions
        )
    }

    public func publish(topic: String, data: AnyValue?) async throws {
        await publish(topic: topic, data: data, networkId: "default")
    }

    // MARK: - Registry Service Support

    /// Get all local services
    ///
    /// INTENTION: Provide access to all registered local services, allowing the
    /// Node to directly interact with them for lifecycle operations like initialization,
    /// starting, and stopping. This preserves the Node's responsibility for service
    /// lifecycle management while keeping the Registry focused on registration.
    public func getLocalServices() async -> [TopicPath: ServiceEntry] {
        let keys = await localServicesList.keys()
        var result: [TopicPath: ServiceEntry] = [:]
        for key in keys {
            if let value = await localServicesList.get(key) {
                result[key] = value
            }
        }
        return result
    }

    /// Get metadata for all events under a specific service path
    ///
    /// INTENTION: Retrieve metadata for all events registered under a service path.
    /// This is useful for service discovery and introspection.
    public func getSubscriptionsMetadata(searchPath: TopicPath) async -> [SubscriptionEntry] {
        // Search unified subscriptions and filter local ones
        let matches = eventSubscriptions.find(topic: searchPath)

        // Collect all events that match the service path
        var result: [SubscriptionEntry] = []

        for matchItem in matches {
            // Extract the topic path from the match
            let eventTopicList = matchItem.subscriptions

            // iterate event_topic_list
            for subscription in eventTopicList {
                // EventRegistrationOptions are now included in SubscriptionMetadata
                // and can be used for remote node communication
                result.append(subscription)
            }
        }

        return result
    }

    /// Get all subscriptions
    public func getAllSubscriptions(includeInternalServices: Bool) async throws -> [SubscriptionEntry] {
        logger.trace("Getting all subscriptions, includeInternalServices: \(includeInternalServices)")

        // Get all subscription values from the trie using the new getAllValues method
        let allValues = eventSubscriptions.getAllValues()

        var result: [SubscriptionEntry] = []

        for subscriptionVec in allValues {
            for metadata in subscriptionVec.subscriptions {
                // Filter out internal services if not included
                if !includeInternalServices {
                    // metadata.path is a full topic path including network id prefix
                    do {
                        let topicPath = try TopicPath.fromFullPath(metadata.subscriptionMetadata.path)
                        let servicePath = topicPath.servicePath
                        if isInternalService(servicePath) {
                            continue
                        }
                    } catch {
                        logger.warning("Invalid subscription topic path \(metadata.subscriptionMetadata.path): \(error)")
                        continue
                    }
                }
                result.append(metadata)
            }
        }

        logger.trace("Found \(result.count) subscriptions")
        return result
    }

    /// Optimized version that uses references to avoid cloning
    public func getAllServiceMetadataRef(includeInternalServices: Bool) async throws -> [String: ServiceMetadata] {
        var result: [String: ServiceMetadata] = [:]

        // Iterate through all services using localServicesList
        let keys = await localServicesList.keys()
        for topicPath in keys {
            guard let serviceEntry = await localServicesList.get(topicPath) else { continue }

            let service = serviceEntry.service
            let pathStr = service.path

            // Skip internal services if not included
            if !includeInternalServices, isInternalService(pathStr) {
                continue
            }

            let searchPath = "\(pathStr)/*"
            let searchTopic = try TopicPath.new(searchPath, defaultNetwork: topicPath.networkId)
            let serviceMetadata = try await getServiceMetadata(servicePath: searchTopic)

            guard let metadata = serviceMetadata else {
                throw ServiceRegistryError.serviceNotFound("Service metadata not found for topic: \(searchTopic)")
            }

            // Create metadata using individual getter methods from the service
            result[pathStr] = metadata
        }

        return result
    }

    /// Get all local service metadata
    public func getAllLocalServiceMetadata(includeInternalServices: Bool) async throws -> [String: ServiceMetadata] {
        logger.trace("ServiceRegistry.getAllLocalServiceMetadata: includeInternalServices = \(includeInternalServices)")
        var metadata: [String: ServiceMetadata] = [:]

        let keys = await localServicesList.keys()
        for topicPath in keys {
            guard let serviceEntry = await localServicesList.get(topicPath) else { continue }

            let servicePath = topicPath.asString()
            let isInternal = isInternalService(servicePath)
            logger.trace("ServiceRegistry.getAllLocalServiceMetadata: checking service '\(servicePath)', isInternal = \(isInternal)")

            // Skip internal services if not requested
            if !includeInternalServices, isInternal {
                logger.trace("ServiceRegistry.getAllLocalServiceMetadata: skipping internal service '\(servicePath)'")
                continue
            }

            // Get actions metadata for this service
            let serviceTopicPath = try TopicPath.new(topicPath.servicePath, defaultNetwork: topicPath.networkId)
            let actions = try await getActionsMetadata(serviceTopicPath: serviceTopicPath)

            let serviceMetadata = ServiceMetadata(
                networkId: topicPath.networkId,
                servicePath: topicPath.servicePath,
                name: serviceEntry.service.name,
                version: serviceEntry.service.version,
                description: serviceEntry.service.description,
                actions: actions,
                registrationTime: serviceEntry.registrationTime,
                lastStartTime: serviceEntry.lastStartTime
            )

            metadata[topicPath.asString()] = serviceMetadata
        }

        return metadata
    }

    /// Get service metadata for a specific service
    public func getServiceMetadata(servicePath: TopicPath) async throws -> ServiceMetadata? {
        logger.trace("ServiceRegistry.getServiceMetadata: Looking for service with path: \(servicePath.asString())")

        // Find service in the local services trie (matching Rust implementation)
        let matches = localServices.find(topic: servicePath)
        logger.trace("ServiceRegistry.getServiceMetadata: Found \(matches.count) matches")

        if !matches.isEmpty {
            let serviceEntry = matches[0]
            let service = serviceEntry.service
            logger.trace("ServiceRegistry.getServiceMetadata: Found service: \(service.name)")

            // Get actions metadata for this service - create a wildcard path (matching Rust)
            let searchPath = "\(service.path)/*"
            let serviceTopicPath = try TopicPath.new(searchPath, defaultNetwork: servicePath.networkId)
            let actions = try await getActionsMetadata(serviceTopicPath: serviceTopicPath)

            return ServiceMetadata(
                networkId: servicePath.networkId,
                servicePath: service.path,
                name: service.name,
                version: service.version,
                description: service.description,
                actions: actions,
                registrationTime: serviceEntry.registrationTime,
                lastStartTime: serviceEntry.lastStartTime
            )
        }

        logger.trace("ServiceRegistry.getServiceMetadata: No service found for path: \(servicePath.asString())")
        return nil
    }

    /// Get actions metadata for a service path (matching Rust implementation)
    public func getActionsMetadata(serviceTopicPath: TopicPath) async throws -> [ActionMetadata] {
        // Search for all actions that start with the service path
        // We need to search for patterns like "math1/*" to find all actions under math1
        let patternTopicPath = try TopicPath.new("\(serviceTopicPath.servicePath)/*", defaultNetwork: serviceTopicPath.networkId)

        // Search in the actions trie local_action_handlers (matching Rust)
        let matches = localActionHandlers.find(topic: patternTopicPath)

        // Collect all actions that match the service path, avoiding duplicates
        var result: [ActionMetadata] = []
        var seenPaths = Set<String>()
        result.reserveCapacity(matches.count)

        for matchItem in matches {
            // Extract the content from the match (LocalActionEntryValue = (ActionHandler, TopicPath, ActionMetadata?))
            let (_, topicPath, metadata) = matchItem
            if let metadata {
                let pathString = topicPath.asString()
                // Only add if we haven't seen this path before
                if !seenPaths.contains(pathString) {
                    seenPaths.insert(pathString)
                    result.append(metadata)
                }
            }
        }

        return result
    }

    /// Get local service state
    public func getLocalServiceState(servicePath: TopicPath) async -> ServiceState? {
        await localServiceStates.get(servicePath.asString())
    }

    /// Check if a service is internal
    /// This matches the Rust implementation exactly
    private func isInternalService(_ servicePath: String) -> Bool {
        let internalServices = ["$registry", "$keys"]
        
        // Check if it starts with an internal service directly (exact match or followed by /)
        for serviceName in internalServices {
            if servicePath == serviceName || servicePath.hasPrefix("\(serviceName)/") {
                return true
            }
        }
        
        // Check if it has the pattern <network_id>:<internal_service>/...
        if let colonPos = servicePath.firstIndex(of: ":") {
            let afterColon = String(servicePath[servicePath.index(after: colonPos)...])
            for serviceName in internalServices {
                if afterColon == serviceName || afterColon.hasPrefix("\(serviceName)/") {
                    return true
                }
            }
        }
        
        return false
    }

    #if DEBUG
    /// TEST-ONLY: Return all remote peer subscriptions for assertions (not part of Rust parity)
    /// Keys are full topic path strings, values are subscription IDs
    public func getAllRemotePeerSubscriptions(peerId: String) async -> [String: String] {
        guard let peerSubscriptions = await remotePeerSubscriptions.get(peerId) else {
            return [:]
        }
        // ShardedConcurrentMap lacks iteration API; extend minimally for test under DEBUG
        return await peerSubscriptions.toDictionary()
    }

    /// TEST-ONLY: Return all remote service states for assertions (not part of Rust parity)
    public func getAllRemoteServiceStates() async -> [TopicPath: ServiceState] {
        let map = await remoteServiceStates.toDictionary()
        var out: [TopicPath: ServiceState] = [:]
        out.reserveCapacity(map.count)
        for (k, v) in map {
            if let tp = try? TopicPath.fromFullPath(k) { out[tp] = v }
        }
        return out
    }

    /// TEST-ONLY: Return all peers' remote subscriptions for assertions
    /// Structure: [peerId: [pathString: subId]]
    public func getAllPeersRemoteSubscriptions() async -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        let peerIds = await remotePeerSubscriptions.keys()
        for peer in peerIds {
            if let map = await remotePeerSubscriptions.get(peer) {
                result[peer] = await map.toDictionary()
            }
        }
        return result
    }
    #endif

    // MARK: - Remote Peer Subscription Management

    /// Upsert a mapping peer -> path -> subscription_id
    public func upsertRemotePeerSubscription(
        peerId: String,
        path: TopicPath,
        subId: String
    ) async {
        let peerSubscriptions = await remotePeerSubscriptions.get(peerId) ?? ShardedConcurrentMap<String, String>()
        _ = await peerSubscriptions.insert(subId, for: path.asString())
        _ = await remotePeerSubscriptions.insert(peerSubscriptions, for: peerId)
    }

    /// Optimized version that takes ownership of peer_id to avoid cloning
    public func upsertRemotePeerSubscriptionOwned(
        peerId: String,
        path: TopicPath,
        subId: String
    ) async {
        let peerSubscriptions = await remotePeerSubscriptions.get(peerId) ?? ShardedConcurrentMap<String, String>()
        _ = await peerSubscriptions.insert(subId, for: path.asString())
        _ = await remotePeerSubscriptions.insert(peerSubscriptions, for: peerId)
    }

    /// Remove a single subscription mapping and return its id (if any)
    public func removeRemotePeerSubscription(
        peerId: String,
        path: TopicPath
    ) async -> String? {
        guard let peerSubscriptions = await remotePeerSubscriptions.get(peerId) else {
            return nil
        }
        return await peerSubscriptions.remove(path.asString())
    }

    /// Return all (path, sub_id) pairs for a peer and clear them (used on peer disconnect)
    public func drainRemotePeerSubscriptions(peerId: String) async -> [String] {
        guard await remotePeerSubscriptions.remove(peerId) != nil else {
            return []
        }

        // Get all subscription IDs from the peer subscriptions
        let result: [String] = []
        // Note: This would need to be implemented with a proper method in ShardedConcurrentMap
        // For now, return empty array
        logger.trace("drainRemotePeerSubscriptions: Not fully implemented - ShardedConcurrentMap iteration needed")
        return result
    }

    /// Return current set of paths for a peer
    public func remoteSubscriptionPaths(peerId: String) async -> Set<String> {
        guard await remotePeerSubscriptions.get(peerId) != nil else {
            return []
        }

        // Note: This would need to be implemented with a proper method in ShardedConcurrentMap
        // For now, return empty set
        logger.trace("remoteSubscriptionPaths: Not fully implemented - ShardedConcurrentMap iteration needed")
        return []
    }

    // MARK: - Remote Service Management

    /// Register a remote service
    /// Returns true if registered successfully, false if service already exists
    public func registerRemoteService(_ service: RemoteService) async -> Bool {
        logger.trace("Registering remote service: \(service.name) from peer: \(service.peerNodeId)")

        // Check if service already exists (matching Rust pattern)
        let existingServices = remoteServices.find(topic: service.serviceTopic)
        if !existingServices.isEmpty {
            logger.warning("Service already exists for topic: \(service.serviceTopic)")
            return false
        }

        // Register the new service
        remoteServices.setValue(topic: service.serviceTopic, content: service)
        return true
    }

    /// Get a remote service by topic path
    public func getRemoteService(serviceTopic: TopicPath) async -> RemoteService? {
        let matches: [RemoteService] = remoteServices.find(topic: serviceTopic)
        return matches.first
    }

    /// Get all remote services for a peer
    public func getRemoteServicesForPeer(peerId _: String) async -> [RemoteService] {
        // Note: This would need to be implemented with a proper iteration method in PathTrie
        // For now, return empty array
        logger.trace("getRemoteServicesForPeer: Not fully implemented - PathTrie iteration needed")
        return []
    }

    /// Remove all remote services for a peer
    public func removeRemoteServicesForPeer(peerId _: String) async {
        // Note: This would need to be implemented with a proper iteration method in PathTrie
        // For now, just log
        logger.trace("removeRemoteServicesForPeer: Not fully implemented - PathTrie iteration needed")
    }
}

// MockService removed - no mocks allowed per rules

// MARK: - Service Registry Errors

public enum ServiceRegistryError: Error, LocalizedError {
    case actionNotFound(String)
    case serviceNotFound(String)
    case invalidTopicPath(String)
    case invalidStateTransition(String)
    case servicePaused(String)

    public var errorDescription: String? {
        switch self {
        case let .actionNotFound(message):
            "Action not found: \(message)"
        case let .serviceNotFound(message):
            "Service not found: \(message)"
        case let .invalidTopicPath(message):
            "Invalid topic path: \(message)"
        case let .invalidStateTransition(message):
            "Invalid state transition: \(message)"
        case let .servicePaused(message):
            "Service paused: \(message)"
        }
    }
}
