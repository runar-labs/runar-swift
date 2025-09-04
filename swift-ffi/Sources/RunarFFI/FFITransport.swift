import CRunarFFI
import Foundation

public struct TransportOptions: Codable {
    public var version: UInt32 = 1
    public var bindAddress: String?
    public var handshakeTimeoutMs: UInt64?
    public var openStreamTimeoutMs: UInt64?
    public var maxMessageSize: UInt64?
    public var logLevel: UInt8? // wire mapped if needed

    public init() {}
}

@available(macOS 11.0, *)
public final class FFITransport {
    var handle: UnsafeMutableRawPointer?

    @available(macOS 11.0, *)
    public init(keys: KeysFFI, optionsCBOR: Data) throws {
        var out: UnsafeMutableRawPointer?
        let (_, error) = withRnError { errPtr in
            optionsCBOR.withUnsafeBytes { rawBuf in
                let ptr = rawBuf.bindMemory(to: UInt8.self).baseAddress
                rn_transport_new_with_keys(keys.rawHandle, ptr, optionsCBOR.count, &out, errPtr)
            }
        }
        if let error { throw error }
        handle = out
    }

    deinit { if let transportHandle = handle { rn_transport_free(transportHandle) } }

    public func start() throws {
        guard let transportHandle = handle else { throw FFIError(code: -1, message: "transport freed") }
        let (_, error) = withRnError { rn_transport_start(transportHandle, $0) }
        if let error { throw error }
    }

    public func stop() throws {
        guard let transportHandle = handle else { throw FFIError(code: -1, message: "transport freed") }
        let (_, error) = withRnError { rn_transport_stop(transportHandle, $0) }
        if let error { throw error }
    }

    public func localAddr() throws -> String {
        guard let transportHandle = handle else { throw FFIError(code: -1, message: "transport freed") }
        var cstr: UnsafeMutablePointer<CChar>?
        var len = 0
        let (_, error) = withRnError { rn_transport_local_addr(transportHandle, &cstr, &len, $0) }
        if let error { throw error }
        defer { if let cString = cstr { rn_string_free(cString) } }
        return cstr.map { String(cString: $0) } ?? ""
    }

    public func connectPeer(_ peerInfoCBOR: Data) throws {
        guard let transportHandle = handle else { throw FFIError(code: -1, message: "transport freed") }
        let (_, error) = withRnError { errPtr in
            peerInfoCBOR.withUnsafeBytes { rawBuf in
                let ptr = rawBuf.bindMemory(to: UInt8.self).baseAddress
                rn_transport_connect_peer(transportHandle, ptr, peerInfoCBOR.count, errPtr)
            }
        }
        if let error { throw error }
    }

    public func disconnectPeer(_ peerNodeId: String) throws {
        guard let transportHandle = handle else { throw FFIError(code: -1, message: "transport freed") }
        let (_, error) = withRnError { rn_transport_disconnect_peer(transportHandle, peerNodeId, $0) }
        if let error { throw error }
    }

    public func isConnected(_ peerNodeId: String) throws -> Bool {
        guard let transportHandle = handle else { throw FFIError(code: -1, message: "transport freed") }
        var connected = false
        let (_, error) = withRnError { rn_transport_is_connected(transportHandle, peerNodeId, &connected, $0) }
        if let error { throw error }
        return connected
    }

    public func updateLocalNodeInfo(_ nodeInfoCBOR: Data) throws {
        guard let transportHandle = handle else { throw FFIError(code: -1, message: "transport freed") }
        let (_, error) = withRnError { errPtr in
            nodeInfoCBOR.withUnsafeBytes { rawBuf in
                let ptr = rawBuf.bindMemory(to: UInt8.self).baseAddress
                rn_transport_update_local_node_info(transportHandle, ptr, nodeInfoCBOR.count, errPtr)
            }
        }
        if let error { throw error }
    }

    // Note: mapping updates are pushed via keys before creating transport
    // (no callback path).

    public func request(
        path: String,
        correlationId: String,
        payload: Data,
        destPeerId: String?,
        profilePublicKey: Data?
    ) throws {
        guard let transportHandle = handle else {
            throw FFIError(code: -1, message: "transport freed")
        }

        let (_, err) = withRnError { errPtr in
            let params = TransportRequestParams(
                transportHandle: transportHandle,
                path: path,
                correlationId: correlationId,
                payload: payload,
                destPeerId: destPeerId,
                profilePublicKey: profilePublicKey,
                errPtr: errPtr
            )
            handleTransportRequest(params)
        }

        if let error = err { throw error }
    }

    public func publish(
        path _: String,
        correlationId _: String,
        payload: Data,
        destPeerId _: String?
    ) throws {
        guard let transportHandle = handle else { throw FFIError(code: -1, message: "transport freed") }
        let (_, err) = withRnError { errPtr in
            payload.withUnsafeBytes { rawBuf in
                let payloadPtr = rawBuf.bindMemory(to: UInt8.self).baseAddress
                rn_transport_publish(transportHandle, payloadPtr, payload.count, errPtr)
            }
        }
        if let error = err { throw error }
    }

    public func completeRequest(requestId _: String, responsePayload: Data, profilePublicKey _: Data?) throws {
        guard let transportHandle = handle else { throw FFIError(code: -1, message: "transport freed") }
        let (_, err) = withRnError { errPtr in
            responsePayload.withUnsafeBytes { rawBuf in
                let payloadPtr = rawBuf.bindMemory(to: UInt8.self).baseAddress
                rn_transport_complete_request(transportHandle, payloadPtr, responsePayload.count, errPtr)
            }
        }
        if let error = err { throw error }
    }

    public func pollEvent() throws -> Data? {
        guard let transportHandle = handle else { throw FFIError(code: -1, message: "transport freed") }
        var buf: UnsafeMutablePointer<UInt8>?
        var len = 0
        let (_, err) = withRnError { rn_transport_poll_event(transportHandle, &buf, &len, $0) }
        if let error = err { throw error }
        guard let buffer = buf, len > 0 else { return nil }
        let data = Data(bytes: buffer, count: len)
        rn_free(buffer, len)
        return data
    }

    // MARK: - Request Handling Support

    private struct TransportRequestParams {
        let transportHandle: UnsafeMutableRawPointer
        let path: String
        let correlationId: String
        let payload: Data
        let destPeerId: String?
        let profilePublicKey: Data?
        let errPtr: UnsafeMutablePointer<RNAPIRnError>?
    }

    private func handleTransportRequest(_: TransportRequestParams) {
        // This function is implemented in the FFITransport+RequestHandling extension
        // to keep the main file focused and under the line limit
    }
}

// keys handle accessed directly
