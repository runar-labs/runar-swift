import Foundation
import SwiftCommon
import RunarSerializer
import RunarFFI

public struct SwiftNetworkConfig {
	public var enabled: Bool
	public var bindAddress: String?
	public var handshakeTimeoutMs: UInt64?
	public var openStreamTimeoutMs: UInt64?
	public var maxMessageSize: Int?
	public init(enabled: Bool = false, bindAddress: String? = nil, handshakeTimeoutMs: UInt64? = nil, openStreamTimeoutMs: UInt64? = nil, maxMessageSize: Int? = nil) {
		self.enabled = enabled
		self.bindAddress = bindAddress
		self.handshakeTimeoutMs = handshakeTimeoutMs
		self.openStreamTimeoutMs = openStreamTimeoutMs
		self.maxMessageSize = maxMessageSize
	}
}

public struct SwiftNodeConfig {
	public var defaultNetworkId: String
	public var networkIds: [String]
	public var requestTimeoutMs: UInt64
	public var network: SwiftNetworkConfig?
	public init(defaultNetworkId: String, networkIds: [String] = [], requestTimeoutMs: UInt64 = 30_000, network: SwiftNetworkConfig? = nil) {
		self.defaultNetworkId = defaultNetworkId
		self.networkIds = Array(Set(networkIds + [defaultNetworkId]))
		self.requestTimeoutMs = requestTimeoutMs
		self.network = network
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
	private var nodeId: String
	private var ffiKeys: FFIKeys?
	private var transport: FFITransport?

	public init(config: SwiftNodeConfig, logger: RunarLogger = RunarLogger(subsystem: "com.runar", category: "node")) {
		self.config = config
		self.logger = logger
		self.registry = ServiceRegistry(logger: logger)
		self.nodeId = "local"
	}

	public func addService(_ service: AbstractService) async throws {
		// Register local service metadata
		registry.registerLocalService(servicePath: service.path, name: service.name, version: service.version, description: service.description)
		let topic = "\(config.defaultNetworkId):\(service.path)"
		let ctx = LifecycleContext(networkId: config.defaultNetworkId, servicePath: service.path, config: nil, logger: logger, nodeDelegate: self)
		try await service.initService(ctx)
		logger.info("Service initialized: \(topic)")
	}

	public func start() async throws {
		logger.info("Node started networkId=\(config.defaultNetworkId)")
		// Internal services registration (scaffolding)
		try await registerInternalServices()
		// Set services running
		registry.setAllLocalServicesRunning()
		// Initialize keys/transport via FFI when networking is enabled
		if config.network?.enabled == true {
			let keys = try FFIKeys()
			self.nodeId = (try? keys.nodeId()) ?? "local"
			self.ffiKeys = keys
			let emptyOptions = Data()
			self.transport = try? FFITransport(keys: keys, optionsCBOR: emptyOptions)
			try? self.transport?.start()
		}
	}

	public func stop() async {
		logger.info("Node stopped")
		do { try transport?.stop() } catch { logger.error("transport stop error: \(error)") }
		transport = nil
		ffiKeys = nil
	}

	private func registerInternalServices() async throws {
		// $registry: list services, service info, state
		let lifecycle = LifecycleContext(networkId: config.defaultNetworkId, servicePath: "$registry", config: nil, logger: logger, nodeDelegate: self)
		try await lifecycle.registerAction("services/list") { _, _ in
			let services = self.registry.getLocalServices()
			let now = UInt64(Date().timeIntervalSince1970)
			let typed: [RegistryServiceMetadata] = services.map { svc in
				RegistryServiceMetadata(
					network_id: self.config.defaultNetworkId,
					service_path: svc.servicePath,
					name: svc.name,
					version: svc.version,
					description: svc.description,
					registration_time: now,
					last_start_time: now
				)
			}
			return AnyValue.struct(typed)
		}
		try await lifecycle.registerAction("services/{service_path}") { _, ctx in
			let path = ctx.servicePath
			if let info = self.registry.getLocalService(servicePath: path) {
				let now = UInt64(Date().timeIntervalSince1970)
				let meta = RegistryServiceMetadata(
					network_id: self.config.defaultNetworkId,
					service_path: info.servicePath,
					name: info.name,
					version: info.version,
					description: info.description,
					registration_time: now,
					last_start_time: now
				)
				return AnyValue.struct(meta)
			}
			return AnyValue.null()
		}
		// $keys: ensure_symmetric_key (placeholder wired to FFI later)
		let keysLifecycle = LifecycleContext(networkId: config.defaultNetworkId, servicePath: "$keys", config: nil, logger: logger, nodeDelegate: self)
		struct EnsureKeyRequest: Codable { let name: String }
		struct EnsureKeyResponse: Codable { let ensured: Bool; let key_name: String }
		try await keysLifecycle.registerAction("ensure_symmetric_key") { params, _ in
			// Expect a typed request later; for now accept string name or struct
			if let p = params, let name: String = try? await p.asType() {
				return AnyValue.struct(EnsureKeyResponse(ensured: true, key_name: name))
			}
			if let p = params, let req: EnsureKeyRequest = try? await p.asType() {
				return AnyValue.struct(EnsureKeyResponse(ensured: true, key_name: req.name))
			}
			return AnyValue.struct(EnsureKeyResponse(ensured: true, key_name: "default"))
		}
	}

	public func request(_ path: String, payload: AnyValue?) async throws -> AnyValue {
		let full = qualify(path)
		if let (handler, params) = registry.getLocalAction(topicPath: full) {
			let ctx = RequestContext(networkId: parseNetwork(full), servicePath: parseService(full), logger: logger, nodeDelegate: self, pathParams: params, userProfilePublicKey: Data())
			return try await handler(payload, ctx)
		}
		// Try remote handlers (round-robin naive)
		let remotes = registry.getRemoteActionHandlers(topicPath: full)
		if let handler = remotes.first {
			let ctx = RequestContext(networkId: parseNetwork(full), servicePath: parseService(full), logger: logger, nodeDelegate: self, pathParams: [:], userProfilePublicKey: Data())
			return try await handler(payload, ctx)
		}
		throw NSError(domain: "SwiftNode", code: 404, userInfo: [NSLocalizedDescriptionKey: "No handler for \(full)"])
	}

	public func publish(_ topic: String, data: AnyValue?) async throws {
		let qualified = qualify(topic)
		let targets = registry.snapshotSubscribers(topicPath: qualified)
		logger.debug("publish to \(qualified) subscribers=\(targets.count)")
		if targets.isEmpty { return }
		for callback in targets {
			let ctx = EventContext(topic: qualified, logger: logger, nodeDelegate: self, isLocal: true)
			do { try await callback(ctx, data) } catch { logger.error("Event handler error: \(error)") }
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
		let full = topic.contains(":") ? topic : qualify(topic)
		return registry.subscribe(topicPath: full, handler: callback)
	}

	public func publish(topic: String, data: AnyValue?) async throws {
		let full = topic.contains(":") ? topic : qualify(topic)
		let targets = registry.snapshotSubscribers(topicPath: full)
		logger.debug("delegate publish to \(full) subscribers=\(targets.count)")
		for callback in targets {
			let ctx = EventContext(topic: full, logger: logger, nodeDelegate: self, isLocal: true)
			do { try await callback(ctx, data) } catch { logger.error("Event handler error: \(error)") }
		}
	}
}
