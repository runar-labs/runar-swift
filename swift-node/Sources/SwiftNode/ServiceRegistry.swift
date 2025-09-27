import Foundation
import RunarSerializer
import SwiftCommon

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

/// Subscription metadata for event subscriptions
public struct SubscriptionMetadata: Sendable, Equatable {
    public let path: String
    public let subscriberKind: SubscriberKind
    public let subscriptionId: String

    public init(path: String, subscriberKind: SubscriberKind, subscriptionId: String) {
        self.path = path
        self.subscriberKind = subscriberKind
        self.subscriptionId = subscriptionId
    }

    public static func == (lhs: SubscriptionMetadata, rhs: SubscriptionMetadata) -> Bool {
        lhs.subscriptionId == rhs.subscriptionId
    }
}

/// Subscriber kind for event subscriptions
public enum SubscriberKind: Sendable {
    case local(EventHandler)
    case remote(String) // node ID
}

/// Subscription vector for managing multiple subscriptions
public struct SubscriptionVec: Sendable, Equatable {
    public let subscriptions: [SubscriptionMetadata]

    public init(subscriptions: [SubscriptionMetadata] = []) {
        self.subscriptions = subscriptions
    }

    public static func == (lhs: SubscriptionVec, rhs: SubscriptionVec) -> Bool {
        lhs.subscriptions == rhs.subscriptions
    }
}

/// Service entry for local services
public struct ServiceEntry {
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

/// Remote service entry
public struct RemoteService: Sendable {
    public let serviceTopic: TopicPath
    public let nodeId: String
    public let state: ServiceState

    public init(serviceTopic: TopicPath, nodeId: String, state: ServiceState = .initialized) {
        self.serviceTopic = serviceTopic
        self.nodeId = nodeId
        self.state = state
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
    private var localServicesList: [TopicPath: ServiceEntry] = [:]

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

    // MARK: - Initialization

    /// Create a new registry with a provided logger
    ///
    /// INTENTION: Initialize a new registry with a logger provided by the parent
    /// component (typically the Node). This ensures proper logger hierarchy.
    /// Matches Rust ServiceRegistry::new() initialization.
    public init(logger: RunarLogger) {
        self.logger = logger
        self.subscriptionIdToTopicPath = ShardedConcurrentMap<String, TopicPath>()
        self.subscriptionIdToServiceTopicPath = ShardedConcurrentMap<String, TopicPath>()
        self.localServicesList = [:]
        self.localServiceStates = ShardedConcurrentMap<String, ServiceState>()
        self.remoteServiceStates = ShardedConcurrentMap<String, ServiceState>()
        self.remotePeerSubscriptions = ShardedConcurrentMap<String, ShardedConcurrentMap<String, String>>()
    }

    // MARK: - Local Service Management

    /// Register a local service instance
    ///
    /// INTENTION: Register a real service instance for use by the node.
    public func registerServiceInstance(
        service: AbstractService,
        networkId: String
    ) async throws {
        let servicePath = service.path
        let serviceTopic = try TopicPath(networkId: networkId, segments: servicePath.split(separator: "/").map(String.init))
        logger.trace("Registering service instance: \(serviceTopic)")

        // Create service entry with real service instance
        let serviceEntry = ServiceEntry(
            serviceTopic: serviceTopic,
            service: service,
            state: .created,
            registrationTime: UInt64(Date().timeIntervalSince1970)
        )

        // Store the service in the local services registry
        localServices.setValue(topic: serviceTopic, content: serviceEntry)
        localServicesList[serviceTopic] = serviceEntry

        // Set initial service state
        _ = await localServiceStates.insert(.initialized, for: serviceTopic.asString())

        logger.trace("Successfully registered service instance: \(serviceTopic)")
    }

    /// Update local service state
    public func updateLocalServiceState(servicePath: String, newState: ServiceState) async throws {
        _ = await localServiceStates.insert(newState, for: servicePath)
        logger.trace("Updated service state for \(servicePath): \(newState.rawValue)")
    }

    /// Start all local services
    public func startAllServices(networkId: String) async throws {
        logger.trace("Starting all local services")

        let services = localServices.getAllEntries(networkId: networkId)

        for serviceEntry in services {
            let context = LifecycleContext(
                networkId: networkId,
                servicePath: serviceEntry.serviceTopic.asString(),
                config: nil,
                logger: logger,
                nodeDelegate: self
            )

            try await serviceEntry.service.start(context)
            try await updateLocalServiceState(
                servicePath: serviceEntry.serviceTopic.asString(),
                newState: ServiceState.running
            )
        }

        logger.trace("All local services started")
    }
    
    /// Get all entries for a specific network
    public func getAllEntries(networkId: String) -> [ServiceEntry] {
        return localServices.getAllEntries(networkId: networkId)
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
        case (.created, .initializing):
            // Valid transition: Created -> Initializing
            try await updateLocalServiceState(servicePath: servicePath.asString(), newState: newState)
        case (.initializing, .initialized):
            // Valid transition: Initializing -> Initialized
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
        case .some(let state):
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
        case .some(let state):
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

        let services = (try? localServices.find(topic: TopicPath(networkId: "default", segments: []))) ?? []

        for serviceEntry in services {
            let context = LifecycleContext(
                networkId: "default",
                servicePath: serviceEntry.serviceTopic.asString(),
                config: nil,
                logger: logger,
                nodeDelegate: self
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

    // MARK: - Action Management

    /// Register a local action handler
    public func registerAction(
        networkId: String,
        servicePath: String,
        action: String,
        handler: @escaping ActionHandler
    ) async throws {
        let topicPath = try TopicPath(networkId: networkId, segments: "\(servicePath)/\(action)".split(separator: "/").map(String.init))
        let metadata = ActionMetadata(
            name: action,
            description: "Action \(action) for service \(servicePath)"
        )
        let entryValue: LocalActionEntryValue = (handler, topicPath, metadata)

        localActionHandlers.setValue(topic: topicPath, content: entryValue)

        logger.trace("Registered action handler for: \(topicPath)")
        logger.trace("Action handler function: \(String(describing: handler))")
    }

    /// Unregister a local action handler
    public func unregisterAction(
        networkId: String,
        servicePath: String,
        action: String
    ) async throws {
        let topicPath = try TopicPath(networkId: networkId, segments: "\(servicePath)/\(action)".split(separator: "/").map(String.init))

        // Remove all handlers for this topic path by setting empty array
        localActionHandlers.setValues(topic: topicPath, contents: [])

        logger.trace("Unregistered action handler for: \(topicPath)")
    }

    // MARK: - Event Management

    /// Subscribe to events
    public func subscribeToEvents(
        networkId: String,
        servicePath: String,
        handler: @escaping EventHandler
    ) async throws -> String {
        let subscriptionId = UUID().uuidString
        let topicPath: TopicPath
        do {
            topicPath = try TopicPath(networkId: networkId, segments: servicePath.split(separator: "/").map(String.init))
        } catch {
            logger.error("Failed to create TopicPath for servicePath '\(servicePath)': \(error)")
            throw ServiceRegistryError.invalidTopicPath(servicePath)
        }

        let subscription = SubscriptionMetadata(
            path: servicePath,
            subscriberKind: .local(handler),
            subscriptionId: subscriptionId
        )

        // Add to event subscriptions
        var existingSubscriptions = eventSubscriptions.find(topic: topicPath).first?.subscriptions ?? []
        logger.trace("Before adding subscription: \(existingSubscriptions.count) existing subscriptions for \(topicPath)")
        existingSubscriptions.append(subscription)
        eventSubscriptions.setValue(topic: topicPath, content: SubscriptionVec(subscriptions: existingSubscriptions))

        // Map subscription ID to topic path
        _ = await subscriptionIdToTopicPath.insert(topicPath, for: subscriptionId)

        logger.trace("Subscribed to events for: \(topicPath) with ID: \(subscriptionId)")
        logger.trace("Total subscriptions for \(topicPath): \(existingSubscriptions.count)")
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

        logger.trace("Unsubscribed from events for: \(topicPath) with ID: \(subscriptionId)")
    }

    // MARK: - Request Handling

    /// Handle a request
    public func request(_ path: String, payload: AnyValue?, networkId: String = "default") async throws -> AnyValue {
        // Strip $ prefix if present (indicates internal service)
        let cleanPath = path.hasPrefix("$") ? String(path.dropFirst()) : path
        let topicPath = try TopicPath(networkId: networkId, segments: cleanPath.split(separator: "/").map(String.init))
        
        logger.trace("ServiceRegistry.request: Looking for handler for path: \(path), topicPath: \(topicPath)")

        // Look up local action handler
        let handlers = localActionHandlers.find(topic: topicPath)
        logger.trace("ServiceRegistry.request: Found \(handlers.count) handlers for path: \(path)")
        for (index, handler) in handlers.enumerated() {
            logger.trace("ServiceRegistry.request: Handler \(index): \(handler)")
        }
        
        // Select the first handler (PathTrie already does template matching)
        guard let entryValue = handlers.first else {
            logger.warning("ServiceRegistry.request: No handler found for path: \(path), topicPath: \(topicPath)")
            throw ServiceRegistryError.actionNotFound("No handler found for path: \(path)")
        }

        logger.trace("ServiceRegistry.request: Found handler for path: \(path)")

        // Extract path parameters from the matched handler
        let pathParams = extractPathParams(requestedPath: path, handlerPath: entryValue.1.actionPath)
        
        // Check if the service is paused before processing the request
        // Only check for non-internal services (skip $registry, $keys, etc.)
        if !cleanPath.hasPrefix("registry") && !cleanPath.hasPrefix("keys") {
            // Try to determine the service path from the topic path
            // For requests like "math/add", the service path would be "math"
            let serviceSegments = topicPath.segments
            if !serviceSegments.isEmpty {
                // Create a service path with just the first segment (service name)
                let servicePath = try TopicPath(networkId: networkId, segments: [serviceSegments[0].asString()])
                if let serviceState = await getLocalServiceState(servicePath: servicePath) {
                    if serviceState == .paused {
                        logger.warning("ServiceRegistry.request: Service '\(serviceSegments[0].asString())' is paused, blocking request to '\(path)'")
                        throw ServiceRegistryError.servicePaused("Service '\(serviceSegments[0].asString())' is paused and cannot process requests")
                    }
                }
            }
        }
        
        // Create request context with path parameters
        let requestContext = RequestContext(
            topicPath: topicPath,
            networkId: networkId,
            metadata: ["payload": payload ?? AnyValue.null()],
            logger: logger,
            pathParams: pathParams,
            nodeDelegate: self
        )

        // Call the handler
        logger.trace("ServiceRegistry.request: Calling handler for path: \(path)")
        logger.trace("ServiceRegistry.request: Handler function: \(String(describing: entryValue.0))")
        let result = try await entryValue.0(payload, requestContext)
        logger.trace("ServiceRegistry.request: Handler returned result for path: \(path): \(result)")
        return result
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
                if handlerSegment.hasPrefix("{") && handlerSegment.hasSuffix("}") {
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
            topicPath = try TopicPath(networkId: networkId, segments: topic.split(separator: "/").map(String.init))
        } catch {
            logger.error("Failed to create TopicPath for topic '\(topic)': \(error)")
            return // Silently fail for event publishing
        }

        // Get subscribers for this topic
        let allMatches = eventSubscriptions.find(topic: topicPath)
        
        // Collect all subscriptions from all matches
        var allSubscriptions: [SubscriptionMetadata] = []
        for match in allMatches {
            allSubscriptions.append(contentsOf: match.subscriptions)
        }
        
        logger.trace("Looking for subscribers for topic: \(topicPath) - found \(allMatches.count) matches with \(allSubscriptions.count) total subscribers")
        for (index, match) in allMatches.enumerated() {
            logger.trace("Match \(index): \(match.subscriptions.count) subscriptions")
        }

        // Notify all subscribers
        for subscription in allSubscriptions {
            switch subscription.subscriberKind {
            case let .local(handler):
                logger.trace("Calling local handler for subscription: \(subscription.subscriptionId)")
                // Call the handler directly with the data
                await handler(data)
            case let .remote(nodeId):
                // Remote event handling would go here
                logger.debug("Remote event for node \(nodeId): \(String(describing: data))")
            }
        }

        logger.trace("Published event to \(allSubscriptions.count) subscribers for topic: \(topic)")
    }

    // MARK: - NodeDelegate Implementation

    public func subscribe(topic: String, options: EventRegistrationOptions?, callback: @escaping EventHandler) async throws -> String {
        try await subscribeToEvents(
            networkId: "default",
            servicePath: topic,
            handler: callback
        )
    }

    public func publish(topic: String, data: AnyValue?) async throws {
        await publish(topic: topic, data: data, networkId: "default")
    }
    
    // MARK: - Registry Service Support
    
    /// Get all local service metadata
    public func getAllLocalServiceMetadata(includeInternalServices: Bool) -> [String: ServiceMetadata] {
        logger.trace("ServiceRegistry.getAllLocalServiceMetadata: includeInternalServices = \(includeInternalServices)")
        var metadata: [String: ServiceMetadata] = [:]
        
        for (topicPath, serviceEntry) in localServicesList {
            let servicePath = topicPath.asString()
            let isInternal = isInternalService(servicePath)
            logger.trace("ServiceRegistry.getAllLocalServiceMetadata: checking service '\(servicePath)', isInternal = \(isInternal)")
            
            // Skip internal services if not requested
            if !includeInternalServices && isInternal {
                logger.trace("ServiceRegistry.getAllLocalServiceMetadata: skipping internal service '\(servicePath)'")
                continue
            }
            
            let serviceMetadata = ServiceMetadata(
                networkId: topicPath.networkId,
                servicePath: topicPath.servicePath,
                name: serviceEntry.service.name,
                version: serviceEntry.service.version,
                description: serviceEntry.service.description,
                actions: [], // TODO: Get actions metadata
                registrationTime: 0, // TODO: Get registration time
                lastStartTime: nil // TODO: Get last start time
            )
            
            metadata[topicPath.asString()] = serviceMetadata
        }
        
        return metadata
    }
    
    /// Get service metadata for a specific service
    public func getServiceMetadata(servicePath: TopicPath) async -> ServiceMetadata? {
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
            let serviceTopicPath = try! TopicPath(networkId: servicePath.networkId, 
                                                segments: searchPath.split(separator: "/").map(String.init))
            let actions = await getActionsMetadata(serviceTopicPath: serviceTopicPath)
            
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
    public func getActionsMetadata(serviceTopicPath: TopicPath) async -> [ActionMetadata] {
        // Search in the actions trie local_action_handlers (matching Rust)
        let matches = localActionHandlers.find(topic: serviceTopicPath)
        
        // Collect all actions that match the service path
        var result: [ActionMetadata] = []
        result.reserveCapacity(matches.count)
        
        for matchItem in matches {
            // Extract the topic path from the match
            let (_, _, metadata) = matchItem
            if let metadata = metadata {
                result.append(metadata)
            }
        }
        
        return result
    }
    
    /// Get local service state
    public func getLocalServiceState(servicePath: TopicPath) async -> ServiceState? {
        await localServiceStates.get(servicePath.asString())
    }
    
    /// Check if a service is internal
    private func isInternalService(_ servicePath: String) -> Bool {
        // Extract just the service path from the full topic path (e.g., "test-network:keys" -> "keys")
        let pathComponents = servicePath.split(separator: ":")
        let actualServicePath = pathComponents.count > 1 ? String(pathComponents[1]) : servicePath
        return actualServicePath == "registry" || actualServicePath == "keys"
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
