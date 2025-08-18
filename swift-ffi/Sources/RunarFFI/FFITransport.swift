import Foundation
import CRunarFFI

public struct TransportOptions: Codable {
	public var v: UInt32 = 1
	public var bind_addr: String?
	public var handshake_timeout_ms: UInt64?
	public var open_stream_timeout_ms: UInt64?
	public var max_message_size: UInt64?
	public var log_level: UInt8? // wire mapped if needed

	public init() {}
}

public final class FFITransport {
	private var handle: UnsafeMutableRawPointer?

	public init(keys: FFIKeys, optionsCBOR: Data) throws {
		var out: UnsafeMutableRawPointer?
		let (_, err) = withRnError { errPtr in
			optionsCBOR.withUnsafeBytes { rawBuf in
				let p = rawBuf.bindMemory(to: UInt8.self).baseAddress
				rn_transport_new_with_keys(keys.handle, p, optionsCBOR.count, &out, errPtr)
			}
		}
		if let e = err { throw e }
		self.handle = out
	}

	deinit { if let h = handle { rn_transport_free(h) } }

	public func start() throws {
		guard let h = handle else { throw FFIError(code: -1, message: "transport freed") }
		let (_, err) = withRnError { rn_transport_start(h, $0) }
		if let e = err { throw e }
	}

	public func stop() throws {
		guard let h = handle else { throw FFIError(code: -1, message: "transport freed") }
		let (_, err) = withRnError { rn_transport_stop(h, $0) }
		if let e = err { throw e }
	}

	public func localAddr() throws -> String {
		guard let h = handle else { throw FFIError(code: -1, message: "transport freed") }
		var cstr: UnsafeMutablePointer<CChar>?
		var len: Int = 0
		let (_, err) = withRnError { rn_transport_local_addr(h, &cstr, &len, $0) }
		if let e = err { throw e }
		defer { if let s = cstr { rn_string_free(s) } }
		return cstr.map { String(cString: $0) } ?? ""
	}

	public func connectPeer(_ peerInfoCBOR: Data) throws {
		guard let h = handle else { throw FFIError(code: -1, message: "transport freed") }
		let (_, err) = withRnError { errPtr in
			peerInfoCBOR.withUnsafeBytes { rawBuf in
				let p = rawBuf.bindMemory(to: UInt8.self).baseAddress
				rn_transport_connect_peer(h, p, peerInfoCBOR.count, errPtr)
			}
		}
		if let e = err { throw e }
	}

	public func disconnectPeer(_ peerNodeId: String) throws {
		guard let h = handle else { throw FFIError(code: -1, message: "transport freed") }
		let (_, err) = withRnError { rn_transport_disconnect_peer(h, peerNodeId, $0) }
		if let e = err { throw e }
	}

	public func isConnected(_ peerNodeId: String) throws -> Bool {
		guard let h = handle else { throw FFIError(code: -1, message: "transport freed") }
		var connected: Bool = false
		let (_, err) = withRnError { rn_transport_is_connected(h, peerNodeId, &connected, $0) }
		if let e = err { throw e }
		return connected
	}

	public func updateLocalNodeInfo(_ nodeInfoCBOR: Data) throws {
		guard let h = handle else { throw FFIError(code: -1, message: "transport freed") }
		let (_, err) = withRnError { errPtr in
			nodeInfoCBOR.withUnsafeBytes { rawBuf in
				let p = rawBuf.bindMemory(to: UInt8.self).baseAddress
				rn_transport_update_local_node_info(h, p, nodeInfoCBOR.count, errPtr)
			}
		}
		if let e = err { throw e }
	}

	public func request(path: String, correlationId: String, payload: Data, destPeerId: String?, profilePublicKey: Data?) throws {
		guard let h = handle else { throw FFIError(code: -1, message: "transport freed") }
		let (_, err) = withRnError { errPtr in
			payload.withUnsafeBytes { payloadRaw in
				let p = payloadRaw.bindMemory(to: UInt8.self).baseAddress
				if let dest = destPeerId {
					if let pk = profilePublicKey {
						pk.withUnsafeBytes { pkRaw in
							let pkp = pkRaw.bindMemory(to: UInt8.self).baseAddress
							rn_transport_request(h, path, correlationId, p, payload.count, dest, pkp, pk.count, errPtr)
						}
					} else {
						rn_transport_request(h, path, correlationId, p, payload.count, dest, nil, 0, errPtr)
					}
				} else {
					if let pk = profilePublicKey {
						pk.withUnsafeBytes { pkRaw in
							let pkp = pkRaw.bindMemory(to: UInt8.self).baseAddress
							rn_transport_request(h, path, correlationId, p, payload.count, nil, pkp, pk.count, errPtr)
						}
					} else {
						rn_transport_request(h, path, correlationId, p, payload.count, nil, nil, 0, errPtr)
					}
				}
			}
		}
		if let e = err { throw e }
	}

	public func publish(path: String, correlationId: String, payload: Data, destPeerId: String?) throws {
		guard let h = handle else { throw FFIError(code: -1, message: "transport freed") }
		let (_, err) = withRnError { errPtr in
			payload.withUnsafeBytes { rawBuf in
				let p = rawBuf.bindMemory(to: UInt8.self).baseAddress
				rn_transport_publish(h, path, correlationId, p, payload.count, destPeerId, errPtr)
			}
		}
		if let e = err { throw e }
	}

	public func completeRequest(requestId: String, responsePayload: Data, profilePublicKey: Data?) throws {
		guard let h = handle else { throw FFIError(code: -1, message: "transport freed") }
		let (_, err) = withRnError { errPtr in
			responsePayload.withUnsafeBytes { rawBuf in
				let p = rawBuf.bindMemory(to: UInt8.self).baseAddress
				if let pk = profilePublicKey {
					pk.withUnsafeBytes { pkRaw in
						let pkp = pkRaw.bindMemory(to: UInt8.self).baseAddress
						rn_transport_complete_request(h, requestId, p, responsePayload.count, pkp, pk.count, errPtr)
					}
				} else {
					rn_transport_complete_request(h, requestId, p, responsePayload.count, nil, 0, errPtr)
				}
			}
		}
		if let e = err { throw e }
	}

	public func pollEvent() throws -> Data? {
		guard let h = handle else { throw FFIError(code: -1, message: "transport freed") }
		var buf: UnsafeMutablePointer<UInt8>?
		var len: Int = 0
		let (_, err) = withRnError { rn_transport_poll_event(h, &buf, &len, $0) }
		if let e = err { throw e }
		guard let b = buf, len > 0 else { return nil }
		let data = Data(bytes: b, count: len)
		rn_free(b, len)
		return data
	}
}

// keys handle accessed directly


