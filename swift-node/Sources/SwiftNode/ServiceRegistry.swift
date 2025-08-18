import Foundation
import RunarSerializer
import SwiftCommon

public typealias ActionHandler = (_ params: AnyValue?, _ ctx: RequestContext) async throws -> AnyValue
public typealias EventHandler = (_ ctx: EventContext, _ data: AnyValue?) async -> Void

public struct EventRegistrationOptions {
	public var includePast: TimeInterval?
	public init(includePast: TimeInterval? = nil) { self.includePast = includePast }
}

final class ServiceRegistry {
	private var localActions: [String: ActionHandler] = [:] // key: full topic path network:service/action
	private var localSubscriptions: [String: [(id: String, handler: EventHandler)]] = [:] // key: full topic path
	private let lock = NSLock()
	private let logger: RunarLogger

	init(logger: RunarLogger) {
		self.logger = logger
	}

	func registerLocalAction(topicPath: String, handler: @escaping ActionHandler) {
		lock.lock(); defer { lock.unlock() }
		localActions[topicPath] = handler
		logger.debug("Registered action \(topicPath)")
	}

	func getLocalAction(topicPath: String) -> ActionHandler? {
		lock.lock(); defer { lock.unlock() }
		return localActions[topicPath]
	}

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
