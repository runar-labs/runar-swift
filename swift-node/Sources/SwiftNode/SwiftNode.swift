import Foundation
import SwiftCommon
import RunarSerializer
import RunarFFI
import SwiftCBOR

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

public struct OnOptions {
	public var timeout: TimeInterval
	public var includePast: TimeInterval?
	public init(timeout: TimeInterval = 5.0, includePast: TimeInterval? = nil) {
		self.timeout = timeout
		self.includePast = includePast
	}
}

public struct PublishOptions {
	public var broadcast: Bool
	public var guaranteedDelivery: Bool
	public var retainFor: TimeInterval?
	public var target: String?
	public init(broadcast: Bool = true, guaranteedDelivery: Bool = false, retainFor: TimeInterval? = nil, target: String? = nil) {
		self.broadcast = broadcast
		self.guaranteedDelivery = guaranteedDelivery
		self.retainFor = retainFor
		self.target = target
	}
}

public final class JoinHandle<T> {
	private let task: Task<Result<Data?, Error>, Never>
	private let mapper: (Result<Data?, Error>) -> T
	public init(task: Task<Result<Data?, Error>, Never>, mapper: @escaping (Result<Data?, Error>) -> T) {
		self.task = task
		self.mapper = mapper
	}
	public func value() async -> T {
		let r = await task.value
		return mapper(r)
	}
	public func cancel() { task.cancel() }
}

actor OneShotBox {
	private var v: Result<Data?, Error>?
	func setIfEmpty(_ nv: Result<Data?, Error>) -> Bool {
		if v == nil { v = nv; return true }
		return false
	}
	func get() -> Result<Data?, Error>? { v }
}

public protocol NodeDelegate {
	func registerAction(networkId: String, servicePath: String, action: String, handler: @escaping ActionHandler) async throws
	func subscribe(topic: String, options: EventRegistrationOptions?, callback: @escaping EventHandler) async throws -> String
	func unsubscribe(_ id: String) async throws
	func publish(topic: String, data: AnyValue?) async throws
}

// Internal abstraction to allow testing without FFI
protocol NodeTransport {
	func start() throws
	func stop() throws
	func pollEvent() throws -> Data?
	func request(path: String, correlationId: String, payload: Data, destPeerId: String?, profilePublicKey: Data?) throws
	func publish(path: String, correlationId: String, payload: Data, destPeerId: String?) throws
	func completeRequest(requestId: String, responsePayload: Data, profilePublicKey: Data?) throws
	func connectPeer(_ peerInfoCBOR: Data) throws
	func disconnectPeer(_ peerNodeId: String) throws
	func isConnected(_ peerNodeId: String) throws -> Bool
	func updateLocalNodeInfo(_ nodeInfoCBOR: Data) throws
	func localAddr() throws -> String
}

extension FFITransport: NodeTransport {}

@MainActor
public final class SwiftNode {
	private let config: SwiftNodeConfig
	private let logger: RunarLogger
	private let registry: ServiceRegistry
	private var nodeId: String
	private var ffiKeys: FFIKeys?
	private var transport: (any NodeTransport)?
	// Discovery integration is available via FFIDiscovery; not auto-started by default
	private var discovery: FFIDiscovery?
	private var eventLoopTask: Task<Void, Never>?
	private final class ContinuationBox { let cont: CheckedContinuation<Data, Error>; init(_ c: CheckedContinuation<Data, Error>) { cont = c } }
	// Removed OnceFlag; use actor OneShotBox for single-result synchronization
	private var pendingByCorrelationId: [String: (box: ContinuationBox, timeoutAt: Date)] = [:]
	// Retained events storage (serial queue for async-safety)
	private let retainedQueue = DispatchQueue(label: "com.runar.swiftnode.retained")
	private var retainedByTopic: [String: [(ts: Date, data: AnyValue)]] = [:]
	private let maxRetainedPerTopic = 16
	private func setPending(_ id: String, box: ContinuationBox, timeoutAt: Date) {
		pendingByCorrelationId[id] = (box, timeoutAt)
	}
	private func takePending(_ id: String) -> ContinuationBox? {
		pendingByCorrelationId.removeValue(forKey: id)?.box
	}

	public init(config: SwiftNodeConfig, logger: RunarLogger = RunarLogger(subsystem: "com.runar", category: "node")) {
		self.config = config
		self.logger = logger
		self.registry = ServiceRegistry(logger: logger)
		self.nodeId = "local"
	}

	// Public initializer allowing dependency injection of pre-provisioned keys
	public init(config: SwiftNodeConfig, keys: FFIKeys, logger: RunarLogger = RunarLogger(subsystem: "com.runar", category: "node")) {
		self.config = config
		self.logger = logger
		self.registry = ServiceRegistry(logger: logger)
		self.nodeId = (try? keys.nodeId()) ?? "local"
		self.ffiKeys = keys
	}

	// Internal/testing initializer to inject a custom transport
	init(config: SwiftNodeConfig, transport: any NodeTransport, logger: RunarLogger = RunarLogger(subsystem: "com.runar", category: "node")) {
		self.config = config
		self.logger = logger
		self.registry = ServiceRegistry(logger: logger)
		self.nodeId = "local"
		self.transport = transport
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
		if let transport {
			try transport.start()
			startEventLoop()
			return
		}
		guard config.network?.enabled == true else { return }
		// Prefer injected keys if available
		let keys: FFIKeys
		if let injected = self.ffiKeys {
			keys = injected
		} else {
			keys = try FFIKeys()
			self.ffiKeys = keys
		}
		// Ensure label resolver is configured (empty mapping satisfies transporter requirement)
		let emptyMapping = CBOR.map([:])
		try keys.setLabelMapping(Data(emptyMapping.encode()))
		self.nodeId = (try? keys.nodeId()) ?? "local"
		// Push initial NodeInfo using configured bind address (may be ephemerally port 0).
		let initialAddrs: [String] = {
			if let b = config.network?.bindAddress, !b.isEmpty { return [b] }
			return []
		}()
		let initialNodeInfo = try buildLocalNodeInfoCBOR(addresses: initialAddrs)
		try keys.setLocalNodeInfo(initialNodeInfo)
		let options = buildTransportOptionsCBOR()
		let ffiTransport = try FFITransport(keys: keys, optionsCBOR: options)
		self.transport = ffiTransport
		try ffiTransport.start()
		// Now update NodeInfo with the actual bound address
		if let addr = try? self.transport?.localAddr() {
			let updated = try buildLocalNodeInfoCBOR(addresses: [addr])
			try self.transport?.updateLocalNodeInfo(updated)
			// Discovery can be started by host explicitly; not enabled by default. Bind events so we can receive PeerDiscovered.
			let disc = try FFIDiscovery(keys: keys, optionsCBOR: Data())
			try disc.initWithOptions(Data())
			try disc.bindEvents(to: ffiTransport)
			self.discovery = disc
		}
		startEventLoop()
	}

	public func stop() async {
		logger.info("Node stopped")
		eventLoopTask?.cancel()
		eventLoopTask = nil
		do { try transport?.stop() } catch { logger.error("transport stop error: \(error)") }
		do { try discovery?.shutdown() } catch { logger.error("discovery shutdown error: \(error)") }
		transport = nil
		discovery = nil
		ffiKeys = nil
	}

	private func startEventLoop() {
		guard eventLoopTask == nil, let transport else { return }
		let log = logger
		eventLoopTask = Task { [weak self] in
			let pollInterval = UInt64(50_000_000) // 50ms
			while let strong = self, !Task.isCancelled {
				do {
					if let data = try transport.pollEvent() {
						await strong.handleTransportEvent(data)
						continue
					}
				} catch {
					log.error("pollEvent error: \(error)")
				}
				try? await Task.sleep(nanoseconds: pollInterval)
			}
		}
	}

	private func handleTransportEvent(_ data: Data) async {
		guard let item = try? CBORDecoder(input: [UInt8](data)).decodeItem(), case let CBOR.map(map) = item else {
			logger.debug("transport event decode failure: invalid CBOR")
			return
		}
		func str(_ k: String) -> String? {
			if let v = map[.utf8String(k)], case let CBOR.utf8String(s) = v { return s }
			return nil
		}
		func bytes(_ k: String) -> Data? {
			if let v = map[.utf8String(k)] {
				switch v {
				case let .byteString(bs): return Data(bs)
				case let .tagged(_, inner): if case let .byteString(bs) = inner { return Data(bs) }
				default: break
				}
			}
			return nil
		}
		guard let type = str("type") else {
			logger.debug("transport event missing type")
			return
		}
		switch type {
		case "ResponseReceived":
			guard let cid = str("correlation_id") else { return }
			let payload = bytes("payload")
			completePending(correlationId: cid, payload: payload)
		case "RequestReceived":
			guard let path = str("path"), let reqId = str("request_id") else { return }
			let payload = bytes("payload")
			do {
				let any = decodeAnyValue(from: payload)
				let result = try await self.request(path, payload: any)
				let respBytes = try result.serialize(context: nil)
				try self.transport?.completeRequest(requestId: reqId, responsePayload: respBytes, profilePublicKey: nil)
			} catch {
				self.logger.error("request handling error: \(error)")
			}
		case "PeerConnected":
			if let peerId = str("peer_node_id") {
				logger.info("peer connected id=\(peerId)")
				// If event carries services list, use it immediately; else query peer registry
				if let bs = bytes("services"),
				   let item = try? CBORDecoder(input: [UInt8](bs)).decodeItem(),
				   case let CBOR.array(arr) = item {
					let services = arr.compactMap { if case let .utf8String(s) = $0 { return s } else { return nil } }
					registry.updatePeerServices(peerNodeId: peerId, servicePaths: services)
				} else {
					do {
						let full = "\(self.config.defaultNetworkId):$registry/services/list"
						let resp = try await self.requestAtPeer(full, payload: nil, peerNodeId: peerId, timeoutMs: self.config.requestTimeoutMs)
						if let metas: [RegistryServiceMetadata] = try? await resp.asType() {
							let svcPaths = metas.map { $0.service_path }
							self.registry.updatePeerServices(peerNodeId: peerId, servicePaths: svcPaths)
						}
					} catch {
						self.logger.debug("peer registry query failed id=\(peerId): \(error)")
					}
				}
			}
		case "PeerDisconnected":
			if let peerId = str("peer_node_id") {
				registry.removePeer(peerId)
				logger.info("peer disconnected id=\(peerId)")
			}
		case "EventReceived":
			// Deliver incoming published events to local subscribers
			if let fullPath = str("path") ?? str("topic") {
				let data = decodeAnyValue(from: bytes("payload"))
				let targets = registry.snapshotSubscribers(topicPath: fullPath)
				for callback in targets {
					let ctx = EventContext(topic: fullPath, logger: logger, nodeDelegate: self, isLocal: false)
					do { try await callback(ctx, data) } catch { self.logger.error("Event handler error: \(error)") }
				}
			}
		case "PeerDiscovered":
			// Auto-connect to discovered peer if peer_info is present
			if let info = bytes("peer_info"), let transport = self.transport as? FFITransport {
				do { try transport.connectPeer(info) } catch { logger.debug("auto-connect on discovery failed: \(error)") }
			}
		default:
			logger.debug("unknown transport event type=\(type)")
		}
	}

	private func completePending(correlationId: String, payload: Data?) {
		if let box = takePending(correlationId) {
			box.cont.resume(returning: payload ?? Data())
		}
	}

	private func decodeAnyValue(from data: Data?) -> AnyValue {
		guard let data, !data.isEmpty else { return AnyValue.null() }
		if let value = try? AnyValue.deserialize(data) {
			return value
		}
		return AnyValue.bytes(data)
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

		// $registry: service state, pause/resume (local only)
		try await lifecycle.registerAction("services/{service_path}/state") { _, ctx in
			let path = ctx.servicePath
			if let entry = self.registry.getLocalService(servicePath: path) {
				return AnyValue.primitive(entry.state.rawValue)
			}
			return AnyValue.null()
		}
		try await lifecycle.registerAction("services/{service_path}/pause") { _, ctx in
			self.registry.updateLocalServiceState(servicePath: ctx.servicePath, newState: .paused)
			return AnyValue.primitive(true)
		}
		try await lifecycle.registerAction("services/{service_path}/resume") { _, ctx in
			self.registry.updateLocalServiceState(servicePath: ctx.servicePath, newState: .running)
			return AnyValue.primitive(true)
		}
	}

	private func buildTransportOptionsCBOR() -> Data {
		struct Opts: Codable {
			let v: UInt32
			let bind_addr: String?
			let handshake_timeout_ms: UInt64?
			let open_stream_timeout_ms: UInt64?
			let max_message_size: UInt64?
		}
		let net = config.network
		let opts = Opts(
			v: 1,
			bind_addr: net?.bindAddress,
			handshake_timeout_ms: net?.handshakeTimeoutMs,
			open_stream_timeout_ms: net?.openStreamTimeoutMs,
			max_message_size: net?.maxMessageSize.map { UInt64($0) }
		)
		let encoder = CodableCBOREncoder()
		return (try? encoder.encode(opts)) ?? Data()
	}

	private func buildLocalNodeInfoCBOR(addresses: [String]) throws -> Data {
		var map: [CBOR: CBOR] = [:]
		let pk = try ffiKeys?.publicKey() ?? Data()
		map[.utf8String("node_public_key")] = .array([UInt8](pk).map { .unsignedInt(UInt64($0)) })
		map[.utf8String("network_ids")] = .array(config.networkIds.map { .utf8String($0) })
		map[.utf8String("addresses")] = .array(addresses.map { .utf8String($0) })
		map[.utf8String("node_metadata")] = .map([
			.utf8String("services"): .array([]),
			.utf8String("subscriptions"): .array([])
		])
		map[.utf8String("version")] = .unsignedInt(0)
		return Data(CBOR.map(map).encode())
	}

	public func request(_ path: String, payload: AnyValue?) async throws -> AnyValue {
		let full = qualify(path)
		if let (handler, params) = registry.getLocalAction(topicPath: full) {
			let ctx = RequestContext(networkId: parseNetwork(full), servicePath: parseService(full), logger: logger, nodeDelegate: self, pathParams: params, userProfilePublicKey: Data())
			return try await handler(payload, ctx)
		}
		// If transport is available, send network request with correlation
		if let transport {
			let correlationId = UUID().uuidString
			let bytes = try payload?.serialize(context: nil) ?? Data()
			let timeout = TimeInterval(config.requestTimeoutMs) / 1000.0
			let responseBytes = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
				// Register pending continuation
				let box = ContinuationBox(continuation)
				setPending(correlationId, box: box, timeoutAt: Date().addingTimeInterval(timeout))
				// Timeout task
				Task { [weak self] in
					try? await Task.sleep(nanoseconds: UInt64(max(0, timeout)) * 1_000_000_000)
					guard let self else { return }
					if let box = self.takePending(correlationId) {
						box.cont.resume(throwing: NSError(domain: "SwiftNode", code: 408, userInfo: [NSLocalizedDescriptionKey: "Request timeout: \(full)"]))
					}
				}
				// Resolve destination peer for the target service if available, else broadcast
				let service = parseService(full)
				let destPeer = registry.nextPeerForService(service)
				do {
					try transport.request(path: full, correlationId: correlationId, payload: bytes, destPeerId: destPeer, profilePublicKey: nil)
				} catch {
					// Fail fast and remove pending
					if let box = self.takePending(correlationId) { box.cont.resume(throwing: error) }
				}
			}
			return decodeAnyValue(from: responseBytes)
		}
		// Try registered remote handlers (round-robin naive) as fallback for tests/dev
		let remotes = registry.getRemoteActionHandlers(topicPath: full)
		if let handler = remotes.first {
			let ctx = RequestContext(networkId: parseNetwork(full), servicePath: parseService(full), logger: logger, nodeDelegate: self, pathParams: [:], userProfilePublicKey: Data())
			return try await handler(payload, ctx)
		}
		throw NSError(domain: "SwiftNode", code: 404, userInfo: [NSLocalizedDescriptionKey: "No handler for \(full)"])
	}

	public func publish(_ topic: String, data: AnyValue?) async throws {
		let options = PublishOptions(broadcast: true, guaranteedDelivery: false, retainFor: nil, target: nil)
		try await publishWithOptions(topic, data: data, options: options)
	}

	public func publish(_ topic: String, data: AnyValue?, retainFor: TimeInterval?) async throws {
		let options = PublishOptions(broadcast: true, guaranteedDelivery: false, retainFor: retainFor, target: nil)
		try await publishWithOptions(topic, data: data, options: options)
	}

	public func publishWithOptions(_ topic: String, data: AnyValue?, options: PublishOptions) async throws {
		let qualified = qualify(topic)
		let targets = registry.snapshotSubscribers(topicPath: qualified)
		logger.debug("publish to \(qualified) subscribers=\(targets.count)")
		for callback in targets {
			let ctx = EventContext(topic: qualified, logger: logger, nodeDelegate: self, isLocal: true)
			do { try await callback(ctx, data) } catch { logger.error("Event handler error: \(error)") }
		}
		// Forward over transport if enabled and requested
		if options.broadcast, let transport {
			let bytes = try data?.serialize(context: nil) ?? Data()
			let correlationId = UUID().uuidString
			try? transport.publish(path: qualified, correlationId: correlationId, payload: bytes, destPeerId: options.target)
		}
		// Retain locally if configured
		if let retain = options.retainFor, retain > 0 {
			let now = Date()
			let cutoff = now.addingTimeInterval(-retain)
			retainedQueue.sync {
				var deque = retainedByTopic[qualified] ?? []
				deque.removeAll { $0.ts < cutoff }
				while deque.count >= maxRetainedPerTopic { _ = deque.removeFirst() }
				deque.append((now, data ?? AnyValue.null()))
				retainedByTopic[qualified] = deque
			}
		}
	}

	public func subscribe(_ topic: String, options: EventRegistrationOptions? = nil, callback: @escaping EventHandler) async throws -> String {
		let full = qualify(topic)
		let id = registry.subscribe(topicPath: full, handler: callback)
		// Deliver past retained event if requested (exact-topic only)
		if let lookback = options?.includePast, lookback > 0 {
			let cutoff = Date().addingTimeInterval(-lookback)
			var latest: (Date, AnyValue)?
			retainedQueue.sync {
				if let deque = retainedByTopic[full] {
					latest = deque.last(where: { $0.ts >= cutoff })
				}
			}
			if let (_, av) = latest {
				let ctx = EventContext(topic: full, logger: logger, nodeDelegate: self, isLocal: true)
				try? await callback(ctx, av)
			}
		}
		return id
	}

	public func on(_ topic: String, options: OnOptions? = nil) -> JoinHandle<Result<AnyValue?, Error>> {
		let full = qualify(topic)
		let opts = options ?? OnOptions()
		let timeoutNs = UInt64(max(0, opts.timeout)) * 1_000_000_000
		let includePast = opts.includePast
		let box = OneShotBox()
		let task: Task<Result<Data?, Error>, Never> = Task { [weak self] in
			guard let self else { return Result<Data?, Error>.failure(NSError(domain: "SwiftNode", code: 1, userInfo: [NSLocalizedDescriptionKey: "Node deallocated"])) }
			let subId = try? await self.subscribe(full, options: nil, callback: { _, data in
				let bytes = (try? data?.serialize(context: nil)) ?? Data()
				_ = await box.setIfEmpty(.success(bytes))
				return
			})
			// includePast immediate delivery
			if let lookback = includePast {
				let cutoff = Date().addingTimeInterval(-lookback)
				var latest: (Date, AnyValue)?
				self.retainedQueue.sync {
					if let deque = self.retainedByTopic[full] { latest = deque.last(where: { $0.ts >= cutoff }) }
				}
				if let (_, av) = latest {
					_ = await box.setIfEmpty(.success((try? av.serialize(context: nil)) ?? Data()))
				}
			}
			// wait for timeout
			try? await Task.sleep(nanoseconds: timeoutNs)
			_ = await box.setIfEmpty(.failure(NSError(domain: "SwiftNode", code: 408, userInfo: [NSLocalizedDescriptionKey: "Timeout waiting for event on topic: \(full)"])) )
			// cleanup
			if let subId { try? await self.unsubscribe(subId) }
			let res = await box.get() ?? Result<Data?, Error>.failure(NSError(domain: "SwiftNode", code: 408, userInfo: [NSLocalizedDescriptionKey: "Timeout waiting for event on topic: \(full)"]))
			return res
		}
		return JoinHandle(task: task) { [weak self] r in
			guard let self else { return .failure(NSError(domain: "SwiftNode", code: 1, userInfo: [NSLocalizedDescriptionKey: "Node deallocated"])) }
			return r.map { bytesOpt in
				guard let b = bytesOpt else { return AnyValue.null() }
				return self.decodeAnyValue(from: b)
			}
		}
	}

	public func unsubscribe(_ id: String) async throws {
		registry.unsubscribe(id: id)
	}

	private func qualify(_ pathOrTopic: String) -> String {
		if pathOrTopic.contains(":") { return pathOrTopic }
		if pathOrTopic.contains("/") { return "\(config.defaultNetworkId):\(pathOrTopic)" }
		return "\(config.defaultNetworkId):default/\(pathOrTopic)"
	}

	// Send a request explicitly to a given peer
	private func requestAtPeer(_ fullPath: String, payload: AnyValue?, peerNodeId: String, timeoutMs: UInt64) async throws -> AnyValue {
		guard let transport else {
			throw NSError(domain: "SwiftNode", code: 503, userInfo: [NSLocalizedDescriptionKey: "Transport not started"])
		}
		let correlationId = UUID().uuidString
		let bytes = try payload?.serialize(context: nil) ?? Data()
		let timeout = TimeInterval(timeoutMs) / 1000.0
		let responseBytes = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
			let box = ContinuationBox(continuation)
			setPending(correlationId, box: box, timeoutAt: Date().addingTimeInterval(timeout))
			Task { [weak self] in
				try? await Task.sleep(nanoseconds: UInt64(max(0, timeout)) * 1_000_000_000)
				guard let self else { return }
				if let box = self.takePending(correlationId) {
					box.cont.resume(throwing: NSError(domain: "SwiftNode", code: 408, userInfo: [NSLocalizedDescriptionKey: "Request timeout: \(fullPath)"]))
				}
			}
			do {
				try transport.request(path: fullPath, correlationId: correlationId, payload: bytes, destPeerId: peerNodeId, profilePublicKey: nil)
			} catch {
				if let box = self.takePending(correlationId) { box.cont.resume(throwing: error) }
			}
		}
		return decodeAnyValue(from: responseBytes)
	}

	public func requestToPeer(_ path: String, payload: AnyValue?, peerNodeId: String, timeoutMs: UInt64? = nil) async throws -> AnyValue {
		let full = qualify(path)
		return try await requestAtPeer(full, payload: payload, peerNodeId: peerNodeId, timeoutMs: timeoutMs ?? config.requestTimeoutMs)
	}

	private func parseNetwork(_ full: String) -> String { full.split(separator: ":").first.map(String.init) ?? config.defaultNetworkId }
	private func parseService(_ full: String) -> String {
		guard let rest = full.split(separator: ":").dropFirst().first else { return "default" }
		let s = String(rest)
		if let idx = s.firstIndex(of: "/") { return String(s[..<idx]) }
		return s
	}
}

// Concurrency sendability allowances for background event handling
// Note: No global Sendable shims here; all state crossing tasks is guarded (actors/queues)
// Removed retroactive Sendable for AnyValue by keeping Data across tasks

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

// Public networking control APIs mirroring Rust Node delegations
extension SwiftNode {
    public func connectPeer(_ peerInfoCBOR: Data) throws {
        try transport?.connectPeer(peerInfoCBOR)
    }

    public func disconnectPeer(_ peerNodeId: String) throws {
        try transport?.disconnectPeer(peerNodeId)
    }

    public func isConnected(_ peerNodeId: String) throws -> Bool {
        try transport?.isConnected(peerNodeId) ?? false
    }

    public func exportPeerInfoCBOR() throws -> Data {
        guard let keys = ffiKeys, let transport else {
            throw NSError(domain: "SwiftNode", code: 503, userInfo: [NSLocalizedDescriptionKey: "Transport not started"])
        }
        let pk = try keys.publicKey()
        let addr = try transport.localAddr()
        var map: [CBOR: CBOR] = [:]
        map[.utf8String("public_key")] = .array([UInt8](pk).map { .unsignedInt(UInt64($0)) })
        map[.utf8String("addresses")] = .array([.utf8String(addr)])
        return Data(CBOR.map(map).encode())
    }
}
