import Foundation
import SwiftCommon
import RunarSerializer

public struct SwiftNodeConfig {
	public var defaultNetworkId: String
	public var networkIds: [String]
	public var requestTimeoutMs: UInt64
	public init(defaultNetworkId: String, networkIds: [String] = [], requestTimeoutMs: UInt64 = 30_000) {
		self.defaultNetworkId = defaultNetworkId
		self.networkIds = Array(Set(networkIds + [defaultNetworkId]))
		self.requestTimeoutMs = requestTimeoutMs
	}
}

public protocol NodeDelegate {
	func registerAction(networkId: String, servicePath: String, action: String, handler: @escaping ActionHandler) async throws
	func subscribe(topic: String, options: EventRegistrationOptions?, callback: @escaping EventHandler) async throws -> String
	func unsubscribe(_ id: String) async throws
	func publish(topic: String, data: AnyValue?) async throws
}

public final class SwiftNode {
	private let config: SwiftNodeConfig
	private let logger: RunarLogger
	private let registry: ServiceRegistry
	private let nodeId: String

	public init(config: SwiftNodeConfig, logger: RunarLogger = RunarLogger(subsystem: "com.runar", category: "node")) {
		self.config = config
		self.logger = logger
		self.registry = ServiceRegistry(logger: logger)
		self.nodeId = "local"
	}

	public func addService(_ service: AbstractService) async throws {
		let topic = "\(config.defaultNetworkId):\(service.path)"
		let ctx = LifecycleContext(networkId: config.defaultNetworkId, servicePath: service.path, config: nil, logger: logger, nodeDelegate: self)
		try await service.initService(ctx)
		logger.info("Service initialized: \(topic)")
	}

	public func start() async throws {
		logger.info("Node started networkId=\(config.defaultNetworkId)")
	}

	public func stop() async {
		logger.info("Node stopped")
	}

	public func request(_ path: String, payload: AnyValue?) async throws -> AnyValue {
		let full = qualify(path)
		guard let handler = registry.getLocalAction(topicPath: full) else {
			throw NSError(domain: "SwiftNode", code: 404, userInfo: [NSLocalizedDescriptionKey: "No handler for \(full)"])
		}
		let ctx = RequestContext(networkId: parseNetwork(full), servicePath: parseService(full), logger: logger, nodeDelegate: self, pathParams: [:], userProfilePublicKey: Data())
		return try await handler(payload, ctx)
	}

	public func publish(_ topic: String, data: AnyValue?) async throws {
		let subs = registry.snapshotSubscribers(topicPath: qualify(topic))
		if subs.isEmpty { return }
		for callback in subs {
			let ctx = EventContext(topic: qualify(topic), logger: logger, nodeDelegate: self, isLocal: true)
			await callback(ctx, data)
		}
	}

	public func subscribe(_ topic: String, options: EventRegistrationOptions? = nil, callback: @escaping EventHandler) async throws -> String {
		registry.subscribe(topicPath: qualify(topic), handler: callback)
	}

	public func unsubscribe(_ id: String) async throws {
		registry.unsubscribe(id: id)
	}

	private func qualify(_ pathOrTopic: String) -> String {
		if pathOrTopic.contains(":") { return pathOrTopic }
		if pathOrTopic.contains("/") { return "\(config.defaultNetworkId):\(pathOrTopic)" }
		return "\(config.defaultNetworkId):default/\(pathOrTopic)"
	}

	private func parseNetwork(_ full: String) -> String { full.split(separator: ":").first.map(String.init) ?? config.defaultNetworkId }
	private func parseService(_ full: String) -> String {
		guard let rest = full.split(separator: ":").dropFirst().first else { return "default" }
		let s = String(rest)
		if let idx = s.firstIndex(of: "/") { return String(s[..<idx]) }
		return s
	}
}

extension SwiftNode: NodeDelegate {
	public func registerAction(networkId: String, servicePath: String, action: String, handler: @escaping ActionHandler) async throws {
		let full = "\(networkId):\(servicePath)/\(action)"
		registry.registerLocalAction(topicPath: full, handler: handler)
	}

	public func subscribe(topic: String, options: EventRegistrationOptions?, callback: @escaping EventHandler) async throws -> String {
		registry.subscribe(topicPath: topic, handler: callback)
	}

	public func publish(topic: String, data: AnyValue?) async throws {
		let subs = registry.snapshotSubscribers(topicPath: topic)
		for callback in subs {
			let ctx = EventContext(topic: topic, logger: logger, nodeDelegate: self, isLocal: true)
			await callback(ctx, data)
		}
	}
}
