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
                let p = rawBuf.bindMemory(to: UInt8.self).baseAddress
                rn_discovery_new_with_multicast(keys.rawHandle, p, optionsCBOR.count, &out, errPtr)
            }
        }
        if let e = err { throw e }
        handle = out
    }

    deinit { if let h = handle { rn_discovery_free(h) } }

    public func initWithOptions(_ optionsCBOR: Data) throws {
        guard let h = handle else { throw FFIError(code: -1, message: "discovery freed") }
        let (_, err) = withRnError { errPtr in
            optionsCBOR.withUnsafeBytes { rawBuf in
                let p = rawBuf.bindMemory(to: UInt8.self).baseAddress
                rn_discovery_init(h, p, optionsCBOR.count, errPtr)
            }
        }
        if let e = err { throw e }
    }

    public func bindEvents(to transport: FFITransport) throws {
        guard let h = handle, let th = transport.handle else { throw FFIError(code: -1, message: "handles freed") }
        let (_, err) = withRnError { rn_discovery_bind_events_to_transport(h, th, $0) }
        if let e = err { throw e }
    }

    public func startAnnouncing() throws {
        guard let h = handle else { throw FFIError(code: -1, message: "discovery freed") }
        let (_, err) = withRnError { rn_discovery_start_announcing(h, $0) }
        if let e = err { throw e }
    }

    public func stopAnnouncing() throws {
        guard let h = handle else { throw FFIError(code: -1, message: "discovery freed") }
        let (_, err) = withRnError { rn_discovery_stop_announcing(h, $0) }
        if let e = err { throw e }
    }

    public func shutdown() throws {
        guard let h = handle else { return }
        let (_, err) = withRnError { rn_discovery_shutdown(h, $0) }
        if let e = err { throw e }
    }

    public func updateLocalPeerInfo(_ peerInfoCBOR: Data) throws {
        guard let h = handle else { throw FFIError(code: -1, message: "discovery freed") }
        let (_, err) = withRnError { errPtr in
            peerInfoCBOR.withUnsafeBytes { rawBuf in
                let p = rawBuf.bindMemory(to: UInt8.self).baseAddress
                rn_discovery_update_local_peer_info(h, p, peerInfoCBOR.count, errPtr)
            }
        }
        if let e = err { throw e }
    }
}
