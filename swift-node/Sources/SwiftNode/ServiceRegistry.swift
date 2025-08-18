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
	private var localActions: [String: ActionHandler] = [:] // key: full topic path network:service/action
	private var localSubscriptions: [String: [(id: String, handler: EventHandler)]] = [:] // key: full topic path
	private var localServices: [String: LocalServiceEntry] = [:] // key: servicePath (no network prefix)
	private var remoteActionHandlers: [String: [ActionHandler]] = [:] // key: full topic path
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
		localActions[topicPath] = handler
		logger.debug("Registered action \(topicPath)")
	}

	func getLocalAction(topicPath: String) -> ActionHandler? {
		lock.lock(); defer { lock.unlock() }
		return localActions[topicPath]
	}

	// MARK: Remote actions (proxies)
	func registerRemoteActionHandler(topicPath: String, handler: @escaping ActionHandler) {
		lock.lock(); defer { lock.unlock() }
		var list = remoteActionHandlers[topicPath, default: []]
		list.append(handler)
		remoteActionHandlers[topicPath] = list
		logger.debug("Registered remote action handler for \(topicPath)")
	}

	func getRemoteActionHandlers(topicPath: String) -> [ActionHandler] {
		lock.lock(); defer { lock.unlock() }
		return remoteActionHandlers[topicPath] ?? []
	}

	// MARK: Subscriptions (local)
	@discardableResult
	func subscribe(topicPath: String, handler: @escaping EventHandler) -> String {
		lock.lock(); defer { lock.unlock() }
		let id = UUID().uuidString
		var list = localSubscriptions[topicPath, default: []]
		list.append((id, handler))
		localSubscriptions[topicPath] = list
		logger.debug("Subscribed to \(topicPath) id=\(id)")
		return id
	}

	func unsubscribe(id: String) {
		lock.lock(); defer { lock.unlock() }
		for (k, v) in localSubscriptions {
			let remaining = v.filter { $0.id != id }
			if remaining.count != v.count { localSubscriptions[k] = remaining }
		}
	}

	func snapshotSubscribers(topicPath: String) -> [EventHandler] {
		lock.lock(); defer { lock.unlock() }
		return localSubscriptions[topicPath]?.map { $0.handler } ?? []
	}
}

private struct DummyNodeDelegate: NodeDelegate {
	func registerAction(networkId: String, servicePath: String, action: String, handler: @escaping ActionHandler) async throws {}
	func subscribe(topic: String, options: EventRegistrationOptions?, callback: @escaping EventHandler) async throws -> String { return "" }
	func unsubscribe(_ id: String) async throws {}
	func publish(topic: String, data: AnyValue?) async throws {}
}
