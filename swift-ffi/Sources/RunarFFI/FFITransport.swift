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
        if let error = error { throw error }
        handle = out
    }

    deinit { if let transportHandle = handle { rn_transport_free(transportHandle) } }

    public func start() throws {
        guard let transportHandle = handle else { throw FFIError(code: -1, message: "transport freed") }
        let (_, error) = withRnError { rn_transport_start(transportHandle, $0) }
        if let error = error { throw error }
    }

    public func stop() throws {
        guard let transportHandle = handle else { throw FFIError(code: -1, message: "transport freed") }
        let (_, error) = withRnError { rn_transport_stop(transportHandle, $0) }
        if let error = error { throw error }
    }

    public func localAddr() throws -> String {
        guard let transportHandle = handle else { throw FFIError(code: -1, message: "transport freed") }
        var cstr: UnsafeMutablePointer<CChar>?
        var len = 0
        let (_, error) = withRnError { rn_transport_local_addr(transportHandle, &cstr, &len, $0) }
        if let error = error { throw error }
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
        if let error = error { throw error }
    }

    public func disconnectPeer(_ peerNodeId: String) throws {
        guard let transportHandle = handle else { throw FFIError(code: -1, message: "transport freed") }
        let (_, error) = withRnError { rn_transport_disconnect_peer(transportHandle, peerNodeId, $0) }
        if let error = error { throw error }
    }

    public func isConnected(_ peerNodeId: String) throws -> Bool {
        guard let transportHandle = handle else { throw FFIError(code: -1, message: "transport freed") }
        var connected = false
        let (_, error) = withRnError { rn_transport_is_connected(transportHandle, peerNodeId, &connected, $0) }
        if let error = error { throw error }
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
        if let error = error { throw error }
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
        guard let transportHandle = handle else { throw FFIError(code: -1, message: "transport freed") }
        let (_, error) = withRnError { errPtr in
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
        if let error = error { throw error }
    }

    public func publish(path: String, correlationId: String, payload: Data, destPeerId: String?) throws {
        print("FFITransport.publish: path=\(path), correlationId=\(correlationId), " +
            "payload.count=\(payload.count), destPeerId=\(destPeerId ?? "nil")")
        guard let transportHandle = handle else { throw FFIError(code: -1, message: "transport freed") }
        let (_, err) = withRnError { errPtr in
            if payload.isEmpty {
                var zero: UInt8 = 0
                let zeroPtr: UnsafePointer<UInt8>? = withUnsafePointer(to: &zero) { $0 }
                let destCString = (destPeerId ?? "").withCString { strdup($0) }
                defer { if let destString = destCString { free(destString) } }
                rn_transport_publish(transportHandle, path, correlationId, zeroPtr, 0, destCString, errPtr)
            } else {
                payload.withUnsafeBytes { rawBuf in
                    let payloadPtr = rawBuf.bindMemory(to: UInt8.self).baseAddress
                    let destCString = (destPeerId ?? "").withCString { strdup($0) }
                    defer { if let destString = destCString { free(destString) } }
                    rn_transport_publish(
                        transportHandle,
                        path,
                        correlationId,
                        payloadPtr,
                        payload.count,
                        destCString,
                        errPtr
                    )
                }
            }
        }
        if let error = err { throw error }
    }

    public func completeRequest(requestId: String, responsePayload: Data, profilePublicKey: Data?) throws {
        guard let transportHandle = handle else { throw FFIError(code: -1, message: "transport freed") }
        let (_, err) = withRnError { errPtr in
            if responsePayload.isEmpty {
                var zero: UInt8 = 0
                let zeroPtr: UnsafePointer<UInt8>? = withUnsafePointer(to: &zero) { $0 }
                if let profileKey = profilePublicKey {
                    profileKey.withUnsafeBytes { pkRaw in
                        let profileKeyPtr = pkRaw.bindMemory(to: UInt8.self).baseAddress
                        rn_transport_complete_request(
                            transportHandle,
                            requestId,
                            zeroPtr,
                            0,
                            profileKeyPtr,
                            profileKey.count,
                            errPtr
                        )
                    }
                } else {
                    var zero: UInt8 = 0
                    let zeroPtr: UnsafePointer<UInt8>? = withUnsafePointer(to: &zero) { $0 }
                    rn_transport_complete_request(
                        transportHandle,
                        requestId,
                        zeroPtr,
                        0,
                        zeroPtr,
                        0,
                        errPtr
                    )
                }
            } else {
                responsePayload.withUnsafeBytes { rawBuf in
                    let payloadPtr = rawBuf.bindMemory(to: UInt8.self).baseAddress
                    if let profileKey = profilePublicKey {
                        profileKey.withUnsafeBytes { pkRaw in
                            let profileKeyPtr = pkRaw.bindMemory(to: UInt8.self).baseAddress
                            rn_transport_complete_request(
                                transportHandle,
                                requestId,
                                payloadPtr,
                                responsePayload.count,
                                profileKeyPtr,
                                profileKey.count,
                                errPtr
                            )
                        }
                    } else {
                        var zero: UInt8 = 0
                        let zeroPtr: UnsafePointer<UInt8>? = withUnsafePointer(to: &zero) { $0 }
                        rn_transport_complete_request(
                            transportHandle,
                            requestId,
                            payloadPtr,
                            responsePayload.count,
                            zeroPtr,
                            0,
                            errPtr
                        )
                    }
                }
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
}

// MARK: - Request Handling Extension

@available(macOS 11.0, *)
extension FFITransport {
    private struct TransportRequestParams {
        let transportHandle: UnsafeMutableRawPointer
        let path: String
        let correlationId: String
        let payload: Data
        let destPeerId: String?
        let profilePublicKey: Data?
        let errPtr: UnsafeMutablePointer<RNAPIRnError>?
    }

    private func handleTransportRequest(_ params: TransportRequestParams) {
        // Prepare non-null C strings for path, correlationId, destPeerId (empty string when nil)
        let destCString = (params.destPeerId ?? "").withCString { strdup($0) }
        defer { if let destString = destCString { free(destString) } }

        if params.payload.isEmpty {
            let emptyParams = EmptyPayloadRequestParams(
                transportHandle: params.transportHandle,
                path: params.path,
                correlationId: params.correlationId,
                destPeerId: params.destPeerId,
                destCString: destCString,
                profilePublicKey: params.profilePublicKey,
                errPtr: params.errPtr
            )
            handleEmptyPayloadRequest(emptyParams)
        } else {
            let payloadParams = PayloadRequestParams(
                transportHandle: params.transportHandle,
                path: params.path,
                correlationId: params.correlationId,
                payload: params.payload,
                destPeerId: params.destPeerId,
                destCString: destCString,
                profilePublicKey: params.profilePublicKey,
                errPtr: params.errPtr
            )
            handlePayloadRequest(payloadParams)
        }
    }

    private struct EmptyPayloadRequestParams {
        let transportHandle: UnsafeMutableRawPointer
        let path: String
        let correlationId: String
        let destPeerId: String?
        let destCString: UnsafeMutablePointer<Int8>?
        let profilePublicKey: Data?
        let errPtr: UnsafeMutablePointer<RNAPIRnError>?
    }

    private func handleEmptyPayloadRequest(_ params: EmptyPayloadRequestParams) {
        var zero: UInt8 = 0
        let zeroPtr: UnsafePointer<UInt8>? = withUnsafePointer(to: &zero) { $0 }

        if let dest = params.destPeerId {
            performEmptyPayloadRequest(params: params, dest: dest, zeroPtr: zeroPtr)
        } else {
            performEmptyPayloadRequestWithCString(params: params, zeroPtr: zeroPtr)
        }
    }

    private func performEmptyPayloadRequest(
        params: EmptyPayloadRequestParams,
        dest: String,
        zeroPtr: UnsafePointer<UInt8>?
    ) {
        if let profileKey = params.profilePublicKey {
            profileKey.withUnsafeBytes { pkRaw in
                let pkp = pkRaw.bindMemory(to: UInt8.self).baseAddress
                rn_transport_request(
                    params.transportHandle,
                    params.path,
                    params.correlationId,
                    zeroPtr,
                    0,
                    dest,
                    pkp,
                    profileKey.count,
                    params.errPtr
                )
            }
        } else {
            rn_transport_request(
                params.transportHandle,
                params.path,
                params.correlationId,
                zeroPtr,
                0,
                dest,
                zeroPtr,
                0,
                params.errPtr
            )
        }
    }

    private func performEmptyPayloadRequestWithCString(
        params: EmptyPayloadRequestParams,
        zeroPtr: UnsafePointer<UInt8>?
    ) {
        if let profileKey = params.profilePublicKey {
            profileKey.withUnsafeBytes { pkRaw in
                let pkp = pkRaw.bindMemory(to: UInt8.self).baseAddress
                rn_transport_request(
                    params.transportHandle,
                    params.path,
                    params.correlationId,
                    zeroPtr,
                    0,
                    params.destCString,
                    pkp,
                    profileKey.count,
                    params.errPtr
                )
            }
        } else {
            rn_transport_request(
                params.transportHandle,
                params.path,
                params.correlationId,
                zeroPtr,
                0,
                params.destCString,
                zeroPtr,
                0,
                params.errPtr
            )
        }
    }

    private struct PayloadRequestParams {
        let transportHandle: UnsafeMutableRawPointer
        let path: String
        let correlationId: String
        let payload: Data
        let destPeerId: String?
        let destCString: UnsafeMutablePointer<Int8>?
        let profilePublicKey: Data?
        let errPtr: UnsafeMutablePointer<RNAPIRnError>?
    }

    private func handlePayloadRequest(_ params: PayloadRequestParams) {
        params.payload.withUnsafeBytes { payloadRaw in
            let payloadPtr = payloadRaw.bindMemory(to: UInt8.self).baseAddress

            if let dest = params.destPeerId {
                if let profileKey = params.profilePublicKey {
                    profileKey.withUnsafeBytes { pkRaw in
                        let pkp = pkRaw.bindMemory(to: UInt8.self).baseAddress
                        rn_transport_request(
                            params.transportHandle,
                            params.path,
                            params.correlationId,
                            payloadPtr,
                            params.payload.count,
                            dest,
                            pkp,
                            profileKey.count,
                            params.errPtr
                        )
                    }
                } else {
                    var zero: UInt8 = 0
                    let zeroPtr: UnsafePointer<UInt8>? = withUnsafePointer(to: &zero) { $0 }
                    rn_transport_request(
                        params.transportHandle,
                        params.path,
                        params.correlationId,
                        payloadPtr,
                        params.payload.count,
                        dest,
                        zeroPtr,
                        0,
                        params.errPtr
                    )
                }
            } else {
                if let profileKey = params.profilePublicKey {
                    profileKey.withUnsafeBytes { pkRaw in
                        let pkp = pkRaw.bindMemory(to: UInt8.self).baseAddress
                        rn_transport_request(
                            params.transportHandle,
                            params.path,
                            params.correlationId,
                            payloadPtr,
                            params.payload.count,
                            params.destCString,
                            pkp,
                            profileKey.count,
                            params.errPtr
                        )
                    }
                } else {
                    var zero: UInt8 = 0
                    let zeroPtr: UnsafePointer<UInt8>? = withUnsafePointer(to: &zero) { $0 }
                    rn_transport_request(
                        params.transportHandle,
                        params.path,
                        params.correlationId,
                        payloadPtr,
                        params.payload.count,
                        params.destCString,
                        zeroPtr,
                        0,
                        params.errPtr
                    )
                }
            }
        }
    }
}

// keys handle accessed directly
