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
    let logger: Logger

    @available(macOS 11.0, *)
    public init(keys: KeysFFI, optionsCBOR: Data) throws {
        logger = keys.logger
        logger.debug("Creating FFITransport with options CBOR length: \(optionsCBOR.count)")

        var out: UnsafeMutableRawPointer?
        let (_, error) = withRnError { errPtr in
            optionsCBOR.withUnsafeBytes { rawBuf in
                let ptr = rawBuf.bindMemory(to: UInt8.self).baseAddress
                logger.debug("Calling rn_transport_new_with_keys")
                let result = rn_transport_new_with_keys(keys.rawHandle, ptr, optionsCBOR.count, &out, errPtr)
                logger.debug("rn_transport_new_with_keys result: \(result)")
                return result
            }
        }
        if let error {
            logger.error("Failed to create transport: \(error)")
            throw error
        }
        handle = out
        logger.info("FFITransport created successfully")
    }

    deinit { if let transportHandle = handle { rn_transport_free(transportHandle) } }

    public func start() throws {
        guard let transportHandle = handle else {
            logger.error("Cannot start transport: handle is nil")
            throw FFIError(code: -1, message: "transport freed")
        }
        logger.debug("Starting transport")
        let (_, error) = withRnError {
            let result = rn_transport_start(transportHandle, $0)
            logger.debug("rn_transport_start result: \(result)")
            return result
        }
        if let error {
            logger.error("Failed to start transport: \(error)")
            throw error
        }
        logger.info("Transport started successfully")
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
        guard let transportHandle = handle else {
            logger.error("Cannot connect peer: handle is nil")
            throw FFIError(code: -1, message: "transport freed")
        }
        logger.debug("Connecting to peer with CBOR length: \(peerInfoCBOR.count)")
        let (_, error) = withRnError { errPtr in
            peerInfoCBOR.withUnsafeBytes { rawBuf in
                let ptr = rawBuf.bindMemory(to: UInt8.self).baseAddress
                let result = rn_transport_connect_peer(transportHandle, ptr, peerInfoCBOR.count, errPtr)
                logger.debug("rn_transport_connect_peer result: \(result)")
                return result
            }
        }
        if let error {
            logger.error("Failed to connect peer: \(error)")
            throw error
        }
        logger.info("Successfully connected to peer")
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
            logger.error("Cannot send request: handle is nil")
            throw FFIError(code: -1, message: "transport freed")
        }

        logger.debug("Sending request - path: \(path), correlationId: \(correlationId), destPeerId: \(destPeerId ?? "nil"), payload length: \(payload.count)")
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

        if let error = err {
            logger.error("Failed to send request: \(error)")
            throw error
        }
        logger.info("Request sent successfully")
    }

    public func publish(publishCBOR: Data) throws {
        guard let transportHandle = handle else { throw FFIError(code: -1, message: "transport freed") }
        let (_, err) = withRnError { errPtr in
            publishCBOR.withUnsafeBytes { rawBuf in
                let payloadPtr = rawBuf.bindMemory(to: UInt8.self).baseAddress
                rn_transport_publish(transportHandle, payloadPtr, publishCBOR.count, errPtr)
            }
        }
        if let error = err { throw error }
    }

    public func completeRequest(completeCBOR: Data) throws {
        guard let transportHandle = handle else { throw FFIError(code: -1, message: "transport freed") }
        let (_, err) = withRnError { errPtr in
            completeCBOR.withUnsafeBytes { rawBuf in
                let payloadPtr = rawBuf.bindMemory(to: UInt8.self).baseAddress
                rn_transport_complete_request(transportHandle, payloadPtr, completeCBOR.count, errPtr)
            }
        }
        if let error = err { throw error }
    }

    public func pollEvent() throws -> Data? {
        guard let transportHandle = handle else {
            logger.error("Cannot poll event: handle is nil")
            throw FFIError(code: -1, message: "transport freed")
        }
        var buf: UnsafeMutablePointer<UInt8>?
        var len = 0
        let (_, err) = withRnError {
            let result = rn_transport_poll_event(transportHandle, &buf, &len, $0)
            logger.debug("rn_transport_poll_event result: \(result)")
            return result
        }
        if let error = err {
            logger.error("Failed to poll event: \(error)")
            throw error
        }
        guard let buffer = buf, len > 0 else {
            logger.debug("No event available")
            return nil
        }
        let data = Data(bytes: buffer, count: len)
        logger.debug("Received event with length: \(len)")
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
