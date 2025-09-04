import CRunarFFI
import Foundation

@available(macOS 11.0, *)

// MARK: - Transport Request Handling

public extension FFITransport {
    /// Send a request with CBOR payload
    func request(requestCBOR: Data) throws {
        guard let transportHandle = handle else {
            throw FFIError.invalidHandle("Transport handle not initialized")
        }

        let (_, err) = withRnError { errPtr in
            requestCBOR.withUnsafeBytes { rawBuf in
                let payloadPtr = rawBuf.bindMemory(to: UInt8.self).baseAddress
                rn_transport_request(transportHandle, payloadPtr, requestCBOR.count, errPtr)
            }
        }
        if let error = err { throw error }
    }
}
