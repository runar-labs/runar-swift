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

    public init(qos: Int = 0, retain: Bool = false) {
        self.qos = qos
        self.retain = retain
    }
}

/// Local action entry value
public struct LocalActionEntryValue: Sendable, Equatable {
    public let handler: ActionHandler
    public let topicPath: TopicPath

    public init(handler: @escaping ActionHandler, topicPath: TopicPath) {
        self.handler = handler
        self.topicPath = topicPath
    }

    public static func == (lhs: LocalActionEntryValue, rhs: LocalActionEntryValue) -> Bool {
        lhs.topicPath == rhs.topicPath
    }
}

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

    public init(serviceTopic: TopicPath, service: AbstractService, state: ServiceState = .initialized) {
        self.serviceTopic = serviceTopic
        self.service = service
        self.state = state
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
public final class ServiceRegistry: NodeDelegate {
    // MARK: - Core Properties

    /// Dispatch queue for thread-safe access to mutable properties
    private let queue = DispatchQueue(label: "com.runar.serviceRegistry", attributes: .concurrent)

    /// Local action handlers organized by path (using PathTrie instead of HashMap)
    /// Store both the handler and the original registration topic path for parameter extraction
    private var localActionHandlers: PathTrie<LocalActionEntryValue> = PathTrie()

    /// Remote action handlers organized by path (using PathTrie instead of HashMap)
    private var remoteActionHandlers: PathTrie<[ActionHandler]> = PathTrie()

    /// Unified event subscriptions – stores both local and remote subscribers in a single trie
    private var eventSubscriptions: PathTrie<SubscriptionVec> = PathTrie()

    /// Map subscription IDs back to TopicPath for efficient unsubscription
    /// (Single dictionary for both local and remote subscriptions)
    private var subscriptionIdToTopicPath: [String: TopicPath] = [:]

    /// Map subscription IDs back to the service TopicPath for efficient unsubscription
    private var subscriptionIdToServiceTopicPath: [String: TopicPath] = [:]

    /// Local services registry (using PathTrie instead of HashMap)
    private var localServices: PathTrie<ServiceEntry> = PathTrie()

    /// Local services list for quick lookup
    private var localServicesList: [String: ServiceEntry] = [:]

    /// Remote services registry (using PathTrie instead of HashMap)
    private var remoteServices: PathTrie<RemoteService> = PathTrie()

    /// Local service lifecycle states
    private var localServiceStates: [String: ServiceState] = [:]

    /// Remote service lifecycle states
    private var remoteServiceStates: [String: ServiceState] = [:]

    /// Mapping of peer node IDs to subscription IDs registered on their behalf
    private var remotePeerSubscriptions: [String: [String: String]] = [:]

    /// Logger instance
    public let logger: RunarLogger

    // MARK: - Initialization

    /// Create a new registry with a provided logger
    ///
    /// INTENTION: Initialize a new registry with a logger provided by the parent
    /// component (typically the Node). This ensures proper logger hierarchy.
    public init(logger: RunarLogger) {
        self.logger = logger
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
        logger.info("Registering service instance: \(serviceTopic)")

        // Create service entry with real service instance
        let serviceEntry = ServiceEntry(
            serviceTopic: serviceTopic,
            service: service,
            state: .created
        )

        // Store the service in the local services registry
        localServices.setValue(topic: serviceTopic, content: serviceEntry)
        localServicesList[servicePath] = serviceEntry

        // Set initial service state
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                self.localServiceStates[servicePath] = ServiceState.initialized
                continuation.resume()
            }
        }

        logger.info("Successfully registered service instance: \(serviceTopic)")
    }

    /// Update local service state
    public func updateLocalServiceState(servicePath: String, newState: ServiceState) async throws {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                self.localServiceStates[servicePath] = newState
                continuation.resume()
            }
        }
        logger.info("Updated service state for \(servicePath): \(newState.rawValue)")
    }

    /// Start all local services
    public func startAllServices() async throws {
        logger.info("Starting all local services")

        let services = (try? localServices.find(topic: TopicPath(networkId: "default", segments: []))) ?? []

        for serviceEntry in services {
            let context = LifecycleContext(
                networkId: "default",
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

        logger.info("All local services started")
    }

    /// Stop all local services
    public func stopAllServices() async {
        logger.info("Stopping all local services")

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

        logger.info("All local services stopped")
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
        let entryValue = LocalActionEntryValue(handler: handler, topicPath: topicPath)

        localActionHandlers.setValue(topic: topicPath, content: entryValue)

        logger.info("Registered action handler for: \(topicPath)")
    }

    /// Unregister a local action handler
    public func unregisterAction(
        networkId: String,
        servicePath: String,
        action: String
    ) async throws {
        let topicPath = try TopicPath(networkId: networkId, segments: "\(servicePath)/\(action)".split(separator: "/").map(String.init))

        // Find and remove the specific handler
        let handlers = localActionHandlers.find(topic: topicPath)
        for handler in handlers {
            localActionHandlers.remove(topic: topicPath, content: handler)
        }

        logger.info("Unregistered action handler for: \(topicPath)")
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
        existingSubscriptions.append(subscription)
        eventSubscriptions.setValue(topic: topicPath, content: SubscriptionVec(subscriptions: existingSubscriptions))

        // Map subscription ID to topic path
        subscriptionIdToTopicPath[subscriptionId] = topicPath

        logger.info("Subscribed to events for: \(topicPath) with ID: \(subscriptionId)")
        return subscriptionId
    }

    /// Unsubscribe from events
    public func unsubscribeFromEvents(subscriptionId: String) async {
        guard let topicPath = subscriptionIdToTopicPath[subscriptionId] else {
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
        subscriptionIdToTopicPath.removeValue(forKey: subscriptionId)

        logger.info("Unsubscribed from events for: \(topicPath) with ID: \(subscriptionId)")
    }

    // MARK: - Request Handling

    /// Handle a request
    public func request(_ path: String, payload: AnyValue?) async throws -> AnyValue {
        let topicPath = try TopicPath(networkId: "default", segments: path.split(separator: "/").map(String.init))

        // Look up local action handler
        let handler = localActionHandlers.find(topic: topicPath).first

        guard let entryValue = handler else {
            throw ServiceRegistryError.actionNotFound("No handler found for path: \(path)")
        }

        // Create request context
        let context = RequestContext(
            networkId: "default",
            servicePath: path,
            logger: logger,
            nodeDelegate: self,
            pathParams: [:],
            userProfilePublicKey: Data()
        )

        // Call the handler
        return try await entryValue.handler(payload)
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
        let subscriptions = eventSubscriptions.find(topic: topicPath).first?.subscriptions ?? []

        // Notify all subscribers
        for subscription in subscriptions {
            switch subscription.subscriberKind {
            case let .local(handler):
                let context = EventContext(
                    topic: topic,
                    logger: logger,
                    nodeDelegate: self,
                    isLocal: true
                )
                await handler(data)
            case let .remote(nodeId):
                // Remote event handling would go here
                logger.debug("Remote event for node \(nodeId): \(data)")
            }
        }

        logger.debug("Published event to \(subscriptions.count) subscribers for topic: \(topic)")
    }

    // MARK: - NodeDelegate Implementation

    public func subscribe(topic: String, options _: EventRegistrationOptions?, callback: @escaping EventHandler) async throws -> String {
        try await subscribeToEvents(
            networkId: "default",
            servicePath: topic,
            handler: callback
        )
    }

    public func publish(topic: String, data: AnyValue?) async throws {
        await publish(topic: topic, data: data, networkId: "default")
    }
}

// MockService removed - no mocks allowed per rules

// MARK: - Service Registry Errors

public enum ServiceRegistryError: Error, LocalizedError {
    case actionNotFound(String)
    case serviceNotFound(String)
    case invalidTopicPath(String)

    public var errorDescription: String? {
        switch self {
        case let .actionNotFound(message):
            "Action not found: \(message)"
        case let .serviceNotFound(message):
            "Service not found: \(message)"
        case let .invalidTopicPath(message):
            "Invalid topic path: \(message)"
        }
    }
}
