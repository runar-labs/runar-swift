import Foundation
import RunarSerializer
import SwiftCommon

public typealias ActionHandler = (_ params: AnyValue?, _ ctx: RequestContext) async throws -> AnyValue
public typealias EventHandler = @Sendable (_ ctx: EventContext, _ data: AnyValue?) async throws -> Void

public struct EventRegistrationOptions {
	public var includePast: TimeInterval?
	public init(includePast: TimeInterval? = nil) { self.includePast = includePast }
}

public enum LocalServiceState: String {
	case initialized
	case running
	case paused
	case stopped
	case error
}

public struct LocalServiceEntry {
	public let servicePath: String
	public let name: String
	public let version: String
	public let description: String
	public let registeredAt: Date
	public var state: LocalServiceState
}

final class ServiceRegistry {
	private var localActions: PathTrie<ActionHandler> = PathTrie()
	private var localSubscriptions: PathTrie<(id: String, handler: EventHandler)> = PathTrie()
	private var localServices: [String: LocalServiceEntry] = [:] // key: servicePath (no network prefix)
	private var remoteActionHandlers: PathTrie<ActionHandler> = PathTrie()
	// Remote service tracking by peer
	private var remoteServicesByPeer: [String: Set<String>] = [:] // peerNodeId -> set(servicePath)
	private var peersByService: [String: [String]] = [:] // servicePath -> ordered peer list for round-robin
	private var rrIndexByService: [String: Int] = [:]
	private let lock = NSLock()
	private let logger: RunarLogger

	init(logger: RunarLogger) {
		self.logger = logger
	}

	// MARK: Local services
	func registerLocalService(servicePath: String, name: String, version: String, description: String) {
		lock.lock(); defer { lock.unlock() }
		localServices[servicePath] = LocalServiceEntry(
			servicePath: servicePath,
			name: name,
			version: version,
			description: description,
			registeredAt: Date(),
			state: .initialized
		)
		logger.debug("Registered local service: \(servicePath)")
	}

	func setAllLocalServicesRunning() {
		lock.lock(); defer { lock.unlock() }
		for (k, v) in localServices { localServices[k] = LocalServiceEntry(servicePath: v.servicePath, name: v.name, version: v.version, description: v.description, registeredAt: v.registeredAt, state: .running) }
	}

	func getLocalServices() -> [LocalServiceEntry] {
		lock.lock(); defer { lock.unlock() }
		return Array(localServices.values)
	}

	func getLocalService(servicePath: String) -> LocalServiceEntry? {
		lock.lock(); defer { lock.unlock() }
		return localServices[servicePath]
	}

	func updateLocalServiceState(servicePath: String, newState: LocalServiceState) {
		lock.lock(); defer { lock.unlock() }
		if let v = localServices[servicePath] {
			localServices[servicePath] = LocalServiceEntry(servicePath: v.servicePath, name: v.name, version: v.version, description: v.description, registeredAt: v.registeredAt, state: newState)
		}
	}

	// MARK: Local actions
	func registerLocalAction(topicPath: String, handler: @escaping ActionHandler) {
		lock.lock(); defer { lock.unlock() }
		localActions.setValue(topic: TopicPath.parse(topicPath), content: handler)
		logger.debug("Registered action \(topicPath)")
	}

	func getLocalAction(topicPath: String) -> (ActionHandler, [String: String])? {
		lock.lock(); defer { lock.unlock() }
		let matches = localActions.findMatches(topic: TopicPath.parse(topicPath))
		if let m = matches.first { return (m.content, m.params) }
		return nil
	}

	// MARK: Remote actions (proxies)
	func registerRemoteActionHandler(topicPath: String, handler: @escaping ActionHandler) {
		lock.lock(); defer { lock.unlock() }
		remoteActionHandlers.appendValue(topic: TopicPath.parse(topicPath), content: handler)
		logger.debug("Registered remote action handler for \(topicPath)")
	}

	func getRemoteActionHandlers(topicPath: String) -> [ActionHandler] {
		lock.lock(); defer { lock.unlock() }
		return remoteActionHandlers.findMatches(topic: TopicPath.parse(topicPath)).map { $0.content }
	}

	// MARK: Remote service presence per peer
	func updatePeerServices(peerNodeId: String, servicePaths: [String]) {
		lock.lock(); defer { lock.unlock() }
		let newSet = Set(servicePaths)
		let oldSet = remoteServicesByPeer[peerNodeId] ?? []
		remoteServicesByPeer[peerNodeId] = newSet
		// Remove peer from services no longer offered
		for svc in oldSet.subtracting(newSet) {
			if var list = peersByService[svc] {
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

	func removePeer(_ peerNodeId: String) {
		lock.lock(); defer { lock.unlock() }
		if let svcs = remoteServicesByPeer.removeValue(forKey: peerNodeId) {
			for svc in svcs {
				if var list = peersByService[svc] {
					peersByService[svc] = list.filter { $0 != peerNodeId }
					if peersByService[svc]?.isEmpty == true { peersByService.removeValue(forKey: svc) }
				}
			}
		}
		// Clear any rr index for services affected
		rrIndexByService.removeAll(keepingCapacity: true)
	}

	func nextPeerForService(_ servicePath: String) -> String? {
		lock.lock(); defer { lock.unlock() }
		guard var list = peersByService[servicePath], !list.isEmpty else { return nil }
		let idx = rrIndexByService[servicePath] ?? 0
		let sel = list[idx % list.count]
		rrIndexByService[servicePath] = (idx + 1) % max(1, list.count)
		return sel
	}

	// MARK: Subscriptions (local)
	@discardableResult
	func subscribe(topicPath: String, handler: @escaping EventHandler) -> String {
		lock.lock(); defer { lock.unlock() }
		let id = UUID().uuidString
		let wrapped: EventHandler = { [logger] ctx, data in
			logger.debug("Delivering event to subscription id=\(id) topic=\(ctx.topic)")
			try await handler(ctx, data)
		}
		localSubscriptions.appendValue(topic: TopicPath.parse(topicPath), content: (id, wrapped))
		logger.debug("Subscribed to \(topicPath) id=\(id)")
		return id
	}

	func unsubscribe(id: String) {
		lock.lock(); defer { lock.unlock() }
		// TODO: maintain index for efficient unsubscription (not needed for current tests)
	}

	func snapshotSubscribers(topicPath: String) -> [EventHandler] {
		lock.lock(); defer { lock.unlock() }
		return localSubscriptions.findMatches(topic: TopicPath.parse(topicPath)).map { $0.content.handler }
	}
}

private struct DummyNodeDelegate: NodeDelegate {
	func registerAction(networkId: String, servicePath: String, action: String, handler: @escaping ActionHandler) async throws {}
	func subscribe(topic: String, options: EventRegistrationOptions?, callback: @escaping EventHandler) async throws -> String { return "" }
	func unsubscribe(_ id: String) async throws {}
	func publish(topic: String, data: AnyValue?) async throws {}
}
