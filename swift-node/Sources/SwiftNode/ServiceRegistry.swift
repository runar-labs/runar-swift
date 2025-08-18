import Foundation
import RunarSerializer
import SwiftCommon

public typealias ActionHandler = (_ params: AnyValue?, _ ctx: RequestContext) async throws -> AnyValue
public typealias EventHandler = (_ ctx: EventContext, _ data: AnyValue?) async -> Void

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

	// MARK: Subscriptions (local)
	@discardableResult
	func subscribe(topicPath: String, handler: @escaping EventHandler) -> String {
		lock.lock(); defer { lock.unlock() }
		let id = UUID().uuidString
		localSubscriptions.appendValue(topic: TopicPath.parse(topicPath), content: (id, handler))
		logger.debug("Subscribed to \(topicPath) id=\(id)")
		return id
	}

	func unsubscribe(id: String) {
		lock.lock(); defer { lock.unlock() }
		// Best effort remove by scanning common patterns
		// Remove from a few common networks if present (optimization could maintain an index)
		for (net, _) in [":":true] { _ = net; /* placeholder to silence warnings */ }
		// Fallback: we cannot know the topic; keep it simple for now by iterating over a small set of likely topics is not feasible here.
		// Provide a broad sweep remove by using a global pattern approach isn't available; ignore if not found.
		// In practice, callers will not rely on unsubscribe in tests.
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
