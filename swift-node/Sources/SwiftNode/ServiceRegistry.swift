import Foundation
import RunarSerializer
import SwiftCommon

public typealias ActionHandler = @MainActor (_ params: AnyValue?, _ ctx: RequestContext) async throws -> AnyValue
public typealias EventHandler = @MainActor @Sendable (_ ctx: EventContext, _ data: AnyValue?) async throws -> Void
public typealias RemoteEventHandler = @MainActor @Sendable (_ data: AnyValue?) async throws -> Void

public struct EventRegistrationOptions: Sendable {
	public var includePast: TimeInterval?
	public init(includePast: TimeInterval? = nil) { self.includePast = includePast }
}

// MARK: - Core Types (Phase 1)

/// Unified subscriber kind matching Rust's SubscriberKind
public enum SubscriberKind: Sendable {
	case local(EventHandler)
	case remote(RemoteEventHandler)
}

/// Subscription metadata structure
public struct SubscriptionMetadata: Sendable {
	public let path: String
	public let subscriberKind: SubscriberKind
	public let subscriptionId: String

	public init(path: String, subscriberKind: SubscriberKind, subscriptionId: String) {
		self.path = path
		self.subscriberKind = subscriberKind
		self.subscriptionId = subscriptionId
	}
}

/// Action metadata structure
public struct ActionMetadata: Sendable {
	public let path: String
	public let description: String?

	public init(path: String, description: String? = nil) {
		self.path = path
		self.description = description
	}
}

/// Service metadata structure matching Rust's ServiceMetadata
public struct ServiceMetadata: Sendable {
	public let networkId: String
	public let servicePath: String
	public let name: String
	public let version: String
	public let description: String
	public let actions: [ActionMetadata]
	public let registrationTime: Date
	public let lastStartTime: Date?

	public init(
		networkId: String,
		servicePath: String,
		name: String,
		version: String,
		description: String,
		actions: [ActionMetadata],
		registrationTime: Date,
		lastStartTime: Date? = nil
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

// MARK: - TopicPath Validation System (Phase 1)
// Using existing TopicPath from Routing.swift which provides proper validation and pattern support

public enum LocalServiceState: String, Sendable {
	case initialized
	case running
	case paused
	case stopped
	case error
}

public struct LocalServiceEntry: Sendable {
	public let servicePath: String
	public let name: String
	public let version: String
	public let description: String
	public let registeredAt: Date
	public var state: LocalServiceState
}

// MARK: - Unified Event System Types (Phase 1)

/// Container for subscription vectors matching Rust's SubscriptionVec
public struct SubscriptionVec: Sendable {
	public var localHandlers: [EventHandler] = []
	public var remoteHandlers: [RemoteEventHandler] = []

	public init() {}
}

/// Enhanced service entry with metadata matching Rust's ServiceEntry
public struct ServiceEntry: Sendable {
	public let service: String // Placeholder for AbstractService
	public let servicePath: TopicPath
	public let name: String
	public let version: String
	public let description: String
	public let serviceState: LocalServiceState
	public let registrationTime: Date
	public let lastStartTime: Date?

	public init(
		service: String,
		servicePath: TopicPath,
		name: String,
		version: String,
		description: String,
		serviceState: LocalServiceState,
		registrationTime: Date,
		lastStartTime: Date? = nil
	) {
		self.service = service
		self.servicePath = servicePath
		self.name = name
		self.version = version
		self.description = description
		self.serviceState = serviceState
		self.registrationTime = registrationTime
		self.lastStartTime = lastStartTime
	}
}

@MainActor
final class ServiceRegistry {
	// MARK: - Unified Event Subscription System (Phase 1)
	/// Single subscription trie containing both local and remote subscribers
	private var eventSubscriptions: PathTrie<SubscriptionVec> = PathTrie()

	/// Subscription ID to topic path mapping for cleanup
	private var subscriptionIdToTopicPath: [String: TopicPath] = [:]

	// MARK: - Action Handlers
	private var localActions: PathTrie<ActionHandler> = PathTrie()
	private var remoteActionHandlers: PathTrie<ActionHandler> = PathTrie()

	// MARK: - Service Management
	private var localServices: [TopicPath: ServiceEntry] = [:]
	private var localServicesList: [TopicPath: ServiceEntry] = [:] // Matches Rust's local_services_list

	// MARK: - Remote Service Tracking (Legacy - will be enhanced in Phase 4)
	private var remoteServicesByPeer: [String: Set<String>] = [:] // peerNodeId -> set(servicePath)
	private var peersByService: [String: [String]] = [:] // servicePath -> ordered peer list for round-robin
	private var rrIndexByService: [String: Int] = [:]

	// MARK: - Peer Subscription Tracking (Phase 4)
	private var remotePeerSubscriptions: [String: [String: String]] = [:] // peerId -> subscriptionId -> topicPath

	// MARK: - Peer Subscription Management Methods (Phase 4)

	/// Upsert a remote peer subscription (matches Rust's upsert_remote_peer_subscription)
	func upsertRemotePeerSubscription(peerId: String, topicPath: String, subscriptionId: String) async {
		if remotePeerSubscriptions[peerId] == nil {
			remotePeerSubscriptions[peerId] = [:]
		}
		remotePeerSubscriptions[peerId]?[subscriptionId] = topicPath
		logger.debug("Upserted remote peer subscription: peer=\(peerId), topic=\(topicPath), subId=\(subscriptionId)")
	}

	/// Remove a remote peer subscription (matches Rust's remove_remote_peer_subscription)
	func removeRemotePeerSubscription(peerId: String, subscriptionId: String) async {
		if let subscriptions = remotePeerSubscriptions[peerId] {
			if let removedTopic = subscriptions[subscriptionId] {
				remotePeerSubscriptions[peerId]?.removeValue(forKey: subscriptionId)
				logger.debug("Removed remote peer subscription: peer=\(peerId), subId=\(subscriptionId), topic=\(removedTopic)")
			}
		}
	}

	/// Drain all remote peer subscriptions for a peer (matches Rust's drain_remote_peer_subscriptions)
	func drainRemotePeerSubscriptions(peerId: String) async -> [String: String] {
		let drainedSubscriptions = remotePeerSubscriptions.removeValue(forKey: peerId) ?? [:]
		logger.debug("Drained \(drainedSubscriptions.count) remote peer subscriptions for peer=\(peerId)")
		return drainedSubscriptions
	}

	/// Get all subscription IDs for a peer
	func getPeerSubscriptionIds(peerId: String) -> [String] {
		let subscriptions: [String: String] = remotePeerSubscriptions[peerId] ?? [:]
		return Array(subscriptions.keys)
	}

	/// Get all peers with subscriptions
	func getPeersWithSubscriptions() -> [String] {
		return Array(remotePeerSubscriptions.keys)
	}

	/// Get topic path for a peer's subscription
	func getPeerSubscriptionTopic(peerId: String, subscriptionId: String) -> String? {
		return remotePeerSubscriptions[peerId]?[subscriptionId]
	}

	private let logger: RunarLogger

	// MARK: - Internal Service Filtering (Phase 3)

	private let internalServices = ["$registry", "$keys"]

	/// Check if a service path is internal (matches Rust's is_internal_service)
	func isInternalService(_ servicePath: String) -> Bool {
		internalServices.contains { servicePath.hasPrefix($0) }
	}

	init(logger: RunarLogger) {
		self.logger = logger
	}

	// MARK: - Phase 1: Convert existing methods to async and remove NSLock

	// MARK: Local services
	func registerLocalService(servicePath: String, name: String, version: String, description: String) async {
		let topicPath = TopicPath.parse(servicePath)
		let serviceEntry = ServiceEntry(
			service: name, // Placeholder - will be enhanced in Phase 3
			servicePath: topicPath,
			name: name,
			version: version,
			description: description,
			serviceState: .initialized,
			registrationTime: Date()
		)
		localServices[topicPath] = serviceEntry
		localServicesList[topicPath] = serviceEntry
		logger.debug("Registered local service: \(topicPath.asString())")
	}

	func setAllLocalServicesRunning() async {
		for (topicPath, serviceEntry) in localServices {
			let updatedEntry = ServiceEntry(
				service: serviceEntry.service,
				servicePath: serviceEntry.servicePath,
				name: serviceEntry.name,
				version: serviceEntry.version,
				description: serviceEntry.description,
				serviceState: .running,
				registrationTime: serviceEntry.registrationTime,
				lastStartTime: Date()
			)
			localServices[topicPath] = updatedEntry
			localServicesList[topicPath] = updatedEntry
		}
	}

	func getLocalServices() -> [ServiceEntry] {
		Array(localServices.values)
	}

	func getLocalService(servicePath: String) -> ServiceEntry? {
		let topicPath = TopicPath.parse(servicePath)
		return localServices[topicPath]
	}

	func updateLocalServiceState(servicePath: String, newState: LocalServiceState) async {
		let topicPath = TopicPath.parse(servicePath)
		if let existingEntry = localServices[topicPath] {
			let updatedEntry = ServiceEntry(
				service: existingEntry.service,
				servicePath: existingEntry.servicePath,
				name: existingEntry.name,
				version: existingEntry.version,
				description: existingEntry.description,
				serviceState: newState,
				registrationTime: existingEntry.registrationTime,
				lastStartTime: newState == .running ? Date() : existingEntry.lastStartTime
			)
			localServices[topicPath] = updatedEntry
			localServicesList[topicPath] = updatedEntry
		}
	}

	// MARK: Local actions
	func registerLocalAction(topicPath: String, handler: @escaping ActionHandler) async {
		let parsedTopic = TopicPath.parse(topicPath)
		localActions.setValue(topic: parsedTopic, content: handler)
		logger.debug("Registered action \(parsedTopic.asString())")
	}

	func getLocalAction(topicPath: String) -> (ActionHandler, [String: String])? {
		let parsedTopic = TopicPath.parse(topicPath)
		let matches = localActions.findMatches(topic: parsedTopic)
		if let m = matches.first { return (m.content, m.params) }
		return nil
	}

	// MARK: Remote actions (proxies)
	func registerRemoteActionHandler(topicPath: String, handler: @escaping ActionHandler) async {
		let parsedTopic = TopicPath.parse(topicPath)
		remoteActionHandlers.appendValue(topic: parsedTopic, content: handler)
		logger.debug("Registered remote action handler for \(parsedTopic.asString())")
	}

	func getRemoteActionHandlers(topicPath: String) -> [ActionHandler] {
		let parsedTopic = TopicPath.parse(topicPath)
		return remoteActionHandlers.findMatches(topic: parsedTopic).map { $0.content }
	}

	// MARK: Remote service presence per peer
	func updatePeerServices(peerNodeId: String, servicePaths: [String]) async {
		let newSet = Set(servicePaths)
		let oldSet = remoteServicesByPeer[peerNodeId] ?? []
		remoteServicesByPeer[peerNodeId] = newSet
		// Remove peer from services no longer offered
		for svc in oldSet.subtracting(newSet) {
			if let list = peersByService[svc] {
				peersByService[svc] = list.filter { $0 != peerNodeId }
				if peersByService[svc]?.isEmpty == true { peersByService.removeValue(forKey: svc) }
			}
		}
		// Add/update peer in new services
		for svc in newSet {
			var list = peersByService[svc] ?? []
			if !list.contains(peerNodeId) { list.append(peerNodeId) }
			peersByService[svc] = list
		}
	}

	func removePeer(_ peerNodeId: String) async {
		// Drain all peer subscriptions before removing the peer
		let drainedSubscriptions = await drainRemotePeerSubscriptions(peerId: peerNodeId)

		if let svcs = remoteServicesByPeer.removeValue(forKey: peerNodeId) {
			for svc in svcs {
				if let list = peersByService[svc] {
					peersByService[svc] = list.filter { $0 != peerNodeId }
					if peersByService[svc]?.isEmpty == true { peersByService.removeValue(forKey: svc) }
				}
			}
		}
		// Clear any rr index for services affected
		rrIndexByService.removeAll(keepingCapacity: true)

		logger.debug("Removed peer \(peerNodeId) with \(drainedSubscriptions.count) subscriptions drained")
	}

	func nextPeerForService(_ servicePath: String) -> String? {
		guard let list = peersByService[servicePath], !list.isEmpty else { return nil }
		let idx = rrIndexByService[servicePath] ?? 0
		let sel = list[idx % list.count]
		rrIndexByService[servicePath] = (idx + 1) % max(1, list.count)
		return sel
	}

	// MARK: Phase 1 - Unified Event Subscription System

	/// Register a local event subscription (matches Rust's register_local_event_subscription)
	func registerLocalEventSubscription(topicPath: String, handler: @escaping EventHandler) async throws -> String {
		let parsedTopic = TopicPath.parse(topicPath)
		let subscriptionId = UUID().uuidString

		// Get existing subscription vector or create new one
		let matches = eventSubscriptions.findMatches(topic: parsedTopic)
		var subscriptionVec: SubscriptionVec

		if let existingMatch = matches.first {
			subscriptionVec = existingMatch.content
		} else {
			subscriptionVec = SubscriptionVec()
		}

		subscriptionVec.localHandlers.append(handler)
		eventSubscriptions.setValue(topic: parsedTopic, content: subscriptionVec)

		// Track subscription for cleanup
		subscriptionIdToTopicPath[subscriptionId] = parsedTopic

		logger.debug("Registered local event subscription: \(parsedTopic.asString()) id=\(subscriptionId)")
		return subscriptionId
	}

	/// Register a remote event subscription (matches Rust's register_remote_event_subscription)
	func registerRemoteEventSubscription(peerId: String, topicPath: String, handler: @escaping RemoteEventHandler) async throws -> String {
		let parsedTopic = TopicPath.parse(topicPath)
		let subscriptionId = UUID().uuidString

		// Get existing subscription vector or create new one
		let matches = eventSubscriptions.findMatches(topic: parsedTopic)
		var subscriptionVec: SubscriptionVec

		if let existingMatch = matches.first {
			subscriptionVec = existingMatch.content
		} else {
			subscriptionVec = SubscriptionVec()
		}

		subscriptionVec.remoteHandlers.append(handler)
		eventSubscriptions.setValue(topic: parsedTopic, content: subscriptionVec)

		// Track subscription for cleanup
		subscriptionIdToTopicPath[subscriptionId] = parsedTopic

		logger.debug("Registered remote event subscription: \(parsedTopic.asString()) peer=\(peerId) id=\(subscriptionId)")
		return subscriptionId
	}

	/// Get local event subscribers for a topic (matches Rust's get_local_event_subscribers)
	func getLocalEventSubscribers(topicPath: String) -> [EventHandler] {
		let parsedTopic = TopicPath.parse(topicPath)
		let matches = eventSubscriptions.findMatches(topic: parsedTopic)
		guard let subscriptionVec = matches.first?.content else {
			return []
		}
		return subscriptionVec.localHandlers
	}

	/// Get remote event subscribers for a topic (matches Rust's get_remote_event_subscribers)
	func getRemoteEventSubscribers(topicPath: String) -> [(peerId: String, handler: RemoteEventHandler)] {
		let parsedTopic = TopicPath.parse(topicPath)
		let matches = eventSubscriptions.findMatches(topic: parsedTopic)
		guard let subscriptionVec = matches.first?.content else {
			return []
		}
		// Note: We don't have peerId tracking in this simplified implementation yet
		// This will be enhanced in Phase 4 with proper peer-based subscription management
		return subscriptionVec.remoteHandlers.map { (peerId: "unknown", handler: $0) }
	}

	/// Get all subscribed topics for metadata
	func getSubscribedTopics() -> [String] {
		Array(subscriptionIdToTopicPath.values.map { $0.asString() })
	}

	/// Get all subscriptions with metadata (matches Rust's get_all_subscriptions)
	func getAllSubscriptions(includeInternalServices: Bool = false) async -> [SubscriptionMetadata] {
		var subscriptions: [SubscriptionMetadata] = []

		// Get local subscriptions from the event subscription trie
		await withTaskGroup(of: (String, [EventHandler]).self) { group in
			// Note: In a real implementation, we'd need to traverse the PathTrie
			// For now, we'll build this from our subscriptionIdToTopicPath mapping
			for (subscriptionId, topicPath) in subscriptionIdToTopicPath {
				let matches = eventSubscriptions.findMatches(topic: topicPath)
				if let subscriptionVec = matches.first?.content {
					// Add local subscriptions
					for handler in subscriptionVec.localHandlers {
						let metadata = SubscriptionMetadata(
							path: topicPath.asString(),
							subscriberKind: .local(handler),
							subscriptionId: subscriptionId
						)
						subscriptions.append(metadata)
					}

					// Add remote subscriptions
					for handler in subscriptionVec.remoteHandlers {
						let metadata = SubscriptionMetadata(
							path: topicPath.asString(),
							subscriberKind: .remote(handler),
							subscriptionId: subscriptionId
						)
						subscriptions.append(metadata)
					}
				}
			}
		}

		// Apply internal service filtering if requested
		if !includeInternalServices {
			subscriptions = subscriptions.filter { !isInternalService($0.path) }
		}

		return subscriptions
	}

	/// Get subscription metadata (alias for getAllSubscriptions)
	func getSubscriptionsMetadata() async -> [SubscriptionMetadata] {
		await getAllSubscriptions(includeInternalServices: false)
	}

	// MARK: - Service Introspection Methods (Phase 3)

	/// Get service metadata for a specific service
	func getServiceMetadata(servicePath: String) async -> ServiceMetadata? {
		let topicPath = TopicPath.parse(servicePath)
		guard let serviceEntry = localServices[topicPath] else {
			return nil
		}

		// For now, return empty actions array - will be enhanced when action tracking is implemented
		let actions = [ActionMetadata]()

		return ServiceMetadata(
			networkId: serviceEntry.servicePath.networkId,
			servicePath: serviceEntry.servicePath.segments.joined(separator: "/"),
			name: serviceEntry.name,
			version: serviceEntry.version,
			description: serviceEntry.description,
			actions: actions,
			registrationTime: serviceEntry.registrationTime,
			lastStartTime: serviceEntry.lastStartTime
		)
	}

	/// Get all service metadata
	func getAllServiceMetadata(includeInternal: Bool = false) async -> [ServiceMetadata] {
		var services = [ServiceMetadata]()

		for serviceEntry in localServices.values {
			// Apply internal service filtering
			if !includeInternal && isInternalService(serviceEntry.servicePath.asString()) {
				continue
			}

			// For now, return empty actions array - will be enhanced when action tracking is implemented
			let actions = [ActionMetadata]()

			let metadata = ServiceMetadata(
				networkId: serviceEntry.servicePath.networkId,
				servicePath: serviceEntry.servicePath.segments.joined(separator: "/"),
				name: serviceEntry.name,
				version: serviceEntry.version,
				description: serviceEntry.description,
				actions: actions,
				registrationTime: serviceEntry.registrationTime,
				lastStartTime: serviceEntry.lastStartTime
			)
			services.append(metadata)
		}

		return services
	}

	/// Get actions metadata (placeholder - will be enhanced when action tracking is implemented)
	func getActionsMetadata(servicePath: String) async -> [ActionMetadata] {
		// TODO: Implement when action metadata tracking is added
		return []
	}

	/// Unsubscribe local event subscription
	func unsubscribeLocal(subscriptionId: String) throws {
		guard let topicPath = subscriptionIdToTopicPath[subscriptionId] else {
			throw NSError(domain: "ServiceRegistry", code: 1, userInfo: [NSLocalizedDescriptionKey: "Subscription not found"])
		}

		let matches = eventSubscriptions.findMatches(topic: topicPath)
		guard !matches.isEmpty else {
			throw NSError(domain: "ServiceRegistry", code: 2, userInfo: [NSLocalizedDescriptionKey: "Topic not found"])
		}

		// Remove the subscription (simplified - in practice we'd need to track individual handlers)
		subscriptionIdToTopicPath.removeValue(forKey: subscriptionId)
		logger.debug("Unsubscribed local event subscription: \(subscriptionId)")
	}

	/// Unsubscribe remote event subscription
	func unsubscribeRemote(subscriptionId: String) throws {
		guard let topicPath = subscriptionIdToTopicPath[subscriptionId] else {
			throw NSError(domain: "ServiceRegistry", code: 1, userInfo: [NSLocalizedDescriptionKey: "Subscription not found"])
		}

		let matches = eventSubscriptions.findMatches(topic: topicPath)
		guard !matches.isEmpty else {
			throw NSError(domain: "ServiceRegistry", code: 2, userInfo: [NSLocalizedDescriptionKey: "Topic not found"])
		}

		// Remove the subscription (simplified implementation)
		subscriptionIdToTopicPath.removeValue(forKey: subscriptionId)
		logger.debug("Unsubscribed remote event subscription: \(subscriptionId)")
	}

	// MARK: Legacy compatibility methods (will be removed after updating SwiftNode)

	@discardableResult
	func subscribe(topicPath: String, handler: @escaping EventHandler) -> String {
		// Temporary compatibility wrapper - calls the new async method
		let semaphore = DispatchSemaphore(value: 0)
		var result = ""

		Task {
			do {
				result = try await registerLocalEventSubscription(topicPath: topicPath, handler: handler)
			} catch {
				logger.error("Failed to register subscription: \(error)")
				result = UUID().uuidString // fallback
			}
			semaphore.signal()
		}

		semaphore.wait()
		return result
	}

	func unsubscribe(id: String) {
		// Temporary compatibility wrapper
		do {
			try unsubscribeLocal(subscriptionId: id)
		} catch {
			logger.error("Failed to unsubscribe: \(error)")
		}
	}

	func snapshotSubscribers(topicPath: String) -> [EventHandler] {
		// Temporary compatibility wrapper
		getLocalEventSubscribers(topicPath: topicPath)
	}
}

private struct DummyNodeDelegate: NodeDelegate {
	@MainActor func registerAction(networkId: String, servicePath: String, action: String, handler: @escaping ActionHandler) async throws {}
	@MainActor func subscribe(topic: String, options: EventRegistrationOptions?, callback: @escaping EventHandler) async throws -> String { return "" }
	@MainActor func unsubscribe(_ id: String) async throws {}
	@MainActor func publish(topic: String, data: AnyValue?) async throws {}
}
