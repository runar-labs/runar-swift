import CRunarFFI
import Foundation

@available(macOS 11.0, *)
public final class FFIDiscovery {
    private var handle: UnsafeMutableRawPointer?

    @available(macOS 11.0, *)
    public init(keys: KeysFFI, optionsCBOR: Data) throws {
        var out: UnsafeMutableRawPointer?
        let (_, err) = withRnError { errPtr in
            optionsCBOR.withUnsafeBytes { rawBuf in
                let rawPtr = rawBuf.bindMemory(to: UInt8.self).baseAddress
                rn_discovery_new_with_multicast(keys.rawHandle, rawPtr, optionsCBOR.count, &out, errPtr)
            }
        }
        if let error = err { throw error }
        handle = out
    }

    deinit { if let discoveryHandle = handle { rn_discovery_free(discoveryHandle) } }

    public func initWithOptions(_ optionsCBOR: Data) throws {
        guard let discoveryHandle = handle else { throw FFIError(code: -1, message: "discovery freed") }
        let (_, err) = withRnError { errPtr in
            optionsCBOR.withUnsafeBytes { rawBuf in
                let rawPtr = rawBuf.bindMemory(to: UInt8.self).baseAddress
                rn_discovery_init(discoveryHandle, rawPtr, optionsCBOR.count, errPtr)
            }
        }
        if let error = err { throw error }
    }

    public func bindEvents(to transport: FFITransport) throws {
        guard let discoveryHandle = handle, let transportHandle = transport.handle else {
            throw FFIError(code: -1, message: "handles freed")
        }
        let (_, err) = withRnError { rn_discovery_bind_events_to_transport(discoveryHandle, transportHandle, $0) }
        if let error = err { throw error }
    }

    public func startAnnouncing() throws {
        guard let discoveryHandle = handle else { throw FFIError(code: -1, message: "discovery freed") }
        let (_, err) = withRnError { rn_discovery_start_announcing(discoveryHandle, $0) }
        if let error = err { throw error }
    }

    public func stopAnnouncing() throws {
        guard let discoveryHandle = handle else { throw FFIError(code: -1, message: "discovery freed") }
        let (_, err) = withRnError { rn_discovery_stop_announcing(discoveryHandle, $0) }
        if let error = err { throw error }
    }

    public func shutdown() throws {
        guard let discoveryHandle = handle else { return }
        let (_, err) = withRnError { rn_discovery_shutdown(discoveryHandle, $0) }
        if let error = err { throw error }
    }

    public func updateLocalPeerInfo(_ peerInfoCBOR: Data) throws {
        guard let discoveryHandle = handle else { throw FFIError(code: -1, message: "discovery freed") }
        let (_, err) = withRnError { errPtr in
            peerInfoCBOR.withUnsafeBytes { rawBuf in
                let rawPtr = rawBuf.bindMemory(to: UInt8.self).baseAddress
                rn_discovery_update_local_peer_info(discoveryHandle, rawPtr, peerInfoCBOR.count, errPtr)
            }
        }
        if let error = err { throw error }
    }
}
