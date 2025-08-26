import CRunarFFI
import Foundation

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

    private struct EmptyPayloadRequestParams {
        let transportHandle: UnsafeMutableRawPointer
        let path: String
        let correlationId: String
        let destPeerId: String?
        let destCString: UnsafeMutablePointer<Int8>?
        let errPtr: UnsafeMutablePointer<RNAPIRnError>?
    }

    private func handleTransportRequest(_ params: TransportRequestParams) {
        if params.payload.isEmpty {
            handleEmptyPayloadRequest(EmptyPayloadRequestParams(
                transportHandle: params.transportHandle,
                path: params.path,
                correlationId: params.correlationId,
                destPeerId: params.destPeerId,
                destCString: nil,
                errPtr: params.errPtr
            ))
        } else {
            handlePayloadRequest(PayloadRequestParams(
                transportHandle: params.transportHandle,
                path: params.path,
                correlationId: params.correlationId,
                payload: params.payload,
                destPeerId: params.destPeerId,
                destCString: nil,
                profilePublicKey: params.profilePublicKey,
                errPtr: params.errPtr
            ))
        }
    }

    private func handleEmptyPayloadRequest(_ params: EmptyPayloadRequestParams) {
        var zero: UInt8 = 0
        let zeroPtr: UnsafePointer<UInt8>? = withUnsafePointer(to: &zero) { $0 }

        if let dest = params.destPeerId {
            performEmptyPayloadRequestWithDest(
                params: params,
                zeroPtr: zeroPtr,
                dest: dest
            )
        } else {
            performEmptyPayloadRequestWithoutDest(
                params: params,
                zeroPtr: zeroPtr
            )
        }
    }

    private func performEmptyPayloadRequestWithDest(
        params: EmptyPayloadRequestParams,
        zeroPtr: UnsafePointer<UInt8>?,
        dest: String
    ) {
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

    private func performEmptyPayloadRequestWithoutDest(
        params: EmptyPayloadRequestParams,
        zeroPtr: UnsafePointer<UInt8>?
    ) {
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
            guard let payloadPtr = payloadRaw.bindMemory(to: UInt8.self).baseAddress else { return }

            if let dest = params.destPeerId {
                performDestinatedRequest(
                    params: params,
                    payloadPtr: payloadPtr,
                    dest: dest
                )
            } else {
                performUndestinatedRequest(
                    params: params,
                    payloadPtr: payloadPtr
                )
            }
        }
    }

    private func performDestinatedRequest(
        params: PayloadRequestParams,
        payloadPtr: UnsafePointer<UInt8>,
        dest: String
    ) {
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
    }

    private func performUndestinatedRequest(
        params: PayloadRequestParams,
        payloadPtr: UnsafePointer<UInt8>
    ) {
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
