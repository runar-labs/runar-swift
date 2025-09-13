import CRunarFFI
import Foundation

// MARK: - Mobile Response Conversion Functions

@available(macOS 11.0, *)
extension MobileKeyManagerImpl {
    /// Convert enrollment response to certificate message
    /// - Parameter response: CBOR-encoded enrollment response
    /// - Returns: CBOR-encoded certificate message
    /// - Throws: FFIError if the operation fails
    func fromEnrollResponse(_ response: Data) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            response.withUnsafeBytes { raw in
                rn_keys_mobile_from_enroll_response(
                    handle,
                    raw.bindMemory(to: UInt8.self).baseAddress,
                    response.count,
                    &out,
                    &outLen,
                    errPtr
                )
            }
        }
        if let error = err { throw error }

        guard let outPtr = out else { return Data() }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return data
    }

    /// Convert renewal response to certificate message
    /// - Parameter response: CBOR-encoded renewal response
    /// - Returns: CBOR-encoded certificate message
    /// - Throws: FFIError if the operation fails
    func fromRenewResponse(_ response: Data) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0

        let (_, err) = withRnError { errPtr in
            response.withUnsafeBytes { raw in
                rn_keys_mobile_from_renew_response(
                    handle,
                    raw.bindMemory(to: UInt8.self).baseAddress,
                    response.count,
                    &out,
                    &outLen,
                    errPtr
                )
            }
        }
        if let error = err { throw error }

        guard let outPtr = out else { return Data() }
        let data = Data(bytes: outPtr, count: outLen)
        rn_free(outPtr, outLen)
        return data
    }
}
